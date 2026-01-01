import 'dart:async';
import 'dart:math';

import 'control_plane_client.dart';
import 'control_plane_models.dart';

class ControlPlaneClientMock implements ControlPlaneClient {
  final _poolUpdatesController = StreamController<PoolUpdate>.broadcast();
  final _leaseUpdatesController = StreamController<LeaseUpdate>.broadcast();

  final Map<String, PoolNode> _nodesById = {};
  final Map<String, Lease> _leasesById = {};
  final List<BillingRecord> _billingHistory = [];
  final Map<String, PricePlan> _priceByKey = {};

  Timer? _heartbeatTimer;
  bool _connected = false;

  ControlPlaneClientMock() {
    _seedPrices();
    _seedNodes();
  }

  @override
  Stream<PoolUpdate> get poolUpdates => _poolUpdatesController.stream;

  @override
  Stream<LeaseUpdate> get leaseUpdates => _leaseUpdatesController.stream;

  @override
  Future<void> connect() async {
    if (_connected) return;
    _connected = true;
    _emitPoolFull();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final now = DateTime.now().toUtc();
      for (final entry in _nodesById.entries) {
        _nodesById[entry.key] = entry.value.copyWith(lastSeen: now);
      }
      _emitPoolFull();
    });
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  @override
  Future<List<PoolNode>> fetchPoolNodes({
    String? region,
    String? gpuTier,
    NodeStatus? status,
  }) async {
    await Future.delayed(const Duration(milliseconds: 150));
    return _nodesById.values.where((node) {
      if (region != null && node.region != region) return false;
      if (gpuTier != null && node.gpuTier != gpuTier) return false;
      if (status != null && node.status != status) return false;
      return true;
    }).toList();
  }

  @override
  Future<RentResult> rent({
    required String region,
    required String gpuTier,
    required BillingUnit billingUnit,
    int count = 1,
    String? clientRequestId,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));

    final candidates = _nodesById.values
        .where((n) =>
            n.region == region &&
            n.gpuTier == gpuTier &&
            n.status == NodeStatus.free)
        .take(count)
        .toList();

    if (candidates.length < count) {
      throw const ControlPlaneApiException(
        code: 'NO_CAPACITY',
        message: 'No free nodes available for the selected region/tier.',
      );
    }

    final now = DateTime.now().toUtc();
    final createdLeases = <Lease>[];
    final tokenMap = <String, String>{};

    for (final node in candidates) {
      final leaseId = _newId(prefix: 'lease');
      final leaseToken = _newToken();

      _nodesById[node.deviceId] =
          node.copyWith(status: NodeStatus.assigned, lastSeen: now);

      final lease = Lease(
        leaseId: leaseId,
        deviceId: node.deviceId,
        status: LeaseStatus.assigned,
        billingUnit: billingUnit,
        unitPrice: _lookupUnitPrice(
            region: region, gpuTier: gpuTier, billingUnit: billingUnit),
        leaseToken: leaseToken,
      );

      _leasesById[leaseId] = lease;
      createdLeases.add(lease);
      tokenMap[leaseId] = leaseToken;
      _emitLeaseUpdate(lease);

      Timer(const Duration(milliseconds: 700), () {
        final existing = _leasesById[leaseId];
        if (existing == null || existing.status == LeaseStatus.ended) return;
        final startedAt = DateTime.now().toUtc();
        final updatedLease = existing.copyWith(
          status: LeaseStatus.active,
          startedAt: startedAt,
        );
        _leasesById[leaseId] = updatedLease;
        final currentNode = _nodesById[node.deviceId];
        if (currentNode != null) {
          _nodesById[node.deviceId] =
              currentNode.copyWith(status: NodeStatus.inUse);
        }
        _emitLeaseUpdate(updatedLease);
        _emitPoolFull();
      });
    }

    _emitPoolFull();

    return RentResult(leases: createdLeases, leaseTokenByLeaseId: tokenMap);
  }

  @override
  Future<List<Lease>> release({
    required List<String> leaseIds,
    String? clientRequestId,
  }) async {
    await Future.delayed(const Duration(milliseconds: 250));

    final endedAt = DateTime.now().toUtc();
    final results = <Lease>[];

    for (final leaseId in leaseIds) {
      final existing = _leasesById[leaseId];
      if (existing == null) {
        continue;
      }
      if (existing.status == LeaseStatus.ended) {
        results.add(existing);
        continue;
      }

      final startedAt = existing.startedAt ?? endedAt;
      final billedUnits = _calculateBilledUnits(
          unit: existing.billingUnit, startedAt: startedAt, endedAt: endedAt);
      final unitPrice = existing.unitPrice ?? 0;
      final amount = unitPrice * billedUnits;

      final endedLease = existing.copyWith(
        status: LeaseStatus.ended,
        endedAt: endedAt,
        endReason: EndReason.userRelease,
        billedUnits: billedUnits,
        amount: amount,
      );

      _leasesById[leaseId] = endedLease;
      results.add(endedLease);
      _emitLeaseUpdate(endedLease);

      _billingHistory.add(BillingRecord(
        recordId: _newId(prefix: 'bill'),
        leaseId: leaseId,
        amount: amount,
        billedUnits: billedUnits,
        billingUnit: existing.billingUnit,
        createdAt: endedAt,
        endReason: EndReason.userRelease,
      ));

      final node = _nodesById[existing.deviceId];
      if (node != null) {
        _nodesById[existing.deviceId] =
            node.copyWith(status: NodeStatus.releasing);

        Timer(const Duration(milliseconds: 600), () {
          final releasingNode = _nodesById[existing.deviceId];
          if (releasingNode == null) return;
          _nodesById[existing.deviceId] = releasingNode.copyWith(
              status: NodeStatus.offline, connectionId: null);
          _emitPoolFull();
        });

        Timer(const Duration(seconds: 2), () {
          final offlineNode = _nodesById[existing.deviceId];
          if (offlineNode == null) return;
          _nodesById[existing.deviceId] = offlineNode.copyWith(
            status: NodeStatus.free,
            connectionId: _newId(prefix: 'conn'),
            lastSeen: DateTime.now().toUtc(),
          );
          _emitPoolFull();
        });
      }
    }

    _emitPoolFull();
    return results;
  }

  @override
  Future<List<Lease>> fetchLeases() async {
    await Future.delayed(const Duration(milliseconds: 150));
    final leases = _leasesById.values
        .where((l) => l.status != LeaseStatus.ended)
        .toList()
      ..sort((a, b) => (b.startedAt ?? DateTime.now())
          .compareTo(a.startedAt ?? DateTime.now()));
    return leases;
  }

  @override
  Future<BillingInfo> fetchBillingInfo() async {
    await Future.delayed(const Duration(milliseconds: 180));
    final activeLeases = _leasesById.values
        .where((l) => l.status != LeaseStatus.ended)
        .toList()
      ..sort((a, b) => a.leaseId.compareTo(b.leaseId));
    final history = List<BillingRecord>.from(_billingHistory)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return BillingInfo(
      currency: 'CNY',
      balance: 1000,
      activeLeases: activeLeases,
      history: history,
    );
  }

  @override
  Future<void> requestRemoteControlLease({
    required String leaseId,
    required Map<String, dynamic> settings,
  }) async {
    await Future.delayed(const Duration(milliseconds: 100));
    // Mock implementation: just log or do nothing as the UI will handle the transition
    // In a real scenario, this would trigger a P2P connection process
    print('Mock: Requested remote control for lease $leaseId with settings $settings');
  }

  @override
  Future<void> deletePoolNode(String deviceId) async {
    print('Mock: deleting node $deviceId');
    _nodesById.remove(deviceId);
    _emitPoolFull();
  }

  void dispose() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _poolUpdatesController.close();
    _leaseUpdatesController.close();
  }

  void _seedPrices() {
    final regions = ['cn-shanghai', 'cn-beijing'];
    final gpuTiers = ['tier_1', 'tier_3', 'tier_5', 'tier_7'];
    for (final region in regions) {
      for (final tier in gpuTiers) {
        _setPrice(
            region: region, tier: tier, unit: BillingUnit.minute, price: 0.5);
        _setPrice(
            region: region, tier: tier, unit: BillingUnit.hour, price: 18);
        _setPrice(
            region: region, tier: tier, unit: BillingUnit.day, price: 200);
        _setPrice(
            region: region, tier: tier, unit: BillingUnit.week, price: 1200);
        _setPrice(
            region: region, tier: tier, unit: BillingUnit.month, price: 3999);
      }
    }
  }

  void _setPrice({
    required String region,
    required String tier,
    required BillingUnit unit,
    required double price,
  }) {
    _priceByKey[_priceKey(region: region, gpuTier: tier, billingUnit: unit)] =
        PricePlan(
      region: region,
      gpuTier: tier,
      billingUnit: unit,
      unitPrice: price,
    );
  }

  void _seedNodes() {
    final now = DateTime.now().toUtc();
    final nodes = <PoolNode>[
      PoolNode(
        deviceId: 'node_001',
        connectionId: _newId(prefix: 'conn'),
        region: 'cn-shanghai',
        gpuTier: 'tier_7',
        status: NodeStatus.free,
        lastSeen: now,
        agentVersion: 'mock-1.0.0',
      ),
      PoolNode(
        deviceId: 'node_002',
        connectionId: _newId(prefix: 'conn'),
        region: 'cn-shanghai',
        gpuTier: 'tier_5',
        status: NodeStatus.free,
        lastSeen: now,
        agentVersion: 'mock-1.0.0',
      ),
      PoolNode(
        deviceId: 'node_003',
        connectionId: _newId(prefix: 'conn'),
        region: 'cn-beijing',
        gpuTier: 'tier_7',
        status: NodeStatus.free,
        lastSeen: now,
        agentVersion: 'mock-1.0.0',
      ),
      PoolNode(
        deviceId: 'node_004',
        connectionId: _newId(prefix: 'conn'),
        region: 'cn-beijing',
        gpuTier: 'tier_3',
        status: NodeStatus.free,
        lastSeen: now,
        agentVersion: 'mock-1.0.0',
      ),
    ];

    for (final node in nodes) {
      _nodesById[node.deviceId] = node;
    }
  }

  double? _lookupUnitPrice({
    required String region,
    required String gpuTier,
    required BillingUnit billingUnit,
  }) {
    return _priceByKey[_priceKey(
            region: region, gpuTier: gpuTier, billingUnit: billingUnit)]
        ?.unitPrice;
  }

  String _priceKey({
    required String region,
    required String gpuTier,
    required BillingUnit billingUnit,
  }) {
    return '$region|$gpuTier|${billingUnit.name}';
  }

  void _emitPoolFull() {
    _poolUpdatesController
        .add(PoolUpdate(isFull: true, nodes: _nodesById.values.toList()));
  }

  void _emitLeaseUpdate(Lease lease) {
    _leaseUpdatesController.add(LeaseUpdate(lease));
  }

  String _newId({required String prefix}) {
    final r = Random.secure();
    final v = (r.nextInt(1 << 30)).toRadixString(16).padLeft(8, '0');
    return '${prefix}_$v';
  }

  String _newToken() {
    final r = Random.secure();
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(48, (_) => alphabet[r.nextInt(alphabet.length)])
        .join();
  }

  int _calculateBilledUnits({
    required BillingUnit unit,
    required DateTime startedAt,
    required DateTime endedAt,
  }) {
    if (!endedAt.isAfter(startedAt)) return 1;

    if (unit == BillingUnit.month) {
      final endMinusEpsilon = endedAt.subtract(const Duration(microseconds: 1));
      final startYm = _yearMonthOf(startedAt.toLocal());
      final endYm = _yearMonthOf(endMinusEpsilon.toLocal());
      final monthsBetween =
          (endYm.year - startYm.year) * 12 + (endYm.month - startYm.month);
      return max(1, monthsBetween + 1);
    }

    final seconds = endedAt.difference(startedAt).inSeconds;
    final unitSeconds = switch (unit) {
      BillingUnit.minute => 60,
      BillingUnit.hour => 3600,
      BillingUnit.day => 86400,
      BillingUnit.week => 604800,
      BillingUnit.month => 0,
    };
    final billed = ((seconds + unitSeconds - 1) ~/ unitSeconds);
    return max(1, billed);
  }

  _YearMonth _yearMonthOf(DateTime dt) => _YearMonth(dt.year, dt.month);
}

class _YearMonth {
  final int year;
  final int month;

  const _YearMonth(this.year, this.month);
}
