import 'dart:async';

import 'package:flutter/foundation.dart';

import 'control_plane_client.dart';
import 'control_plane_models.dart';

class ControlPlaneController extends ChangeNotifier {
  final ControlPlaneClient _client;

  List<PoolNode> poolNodes = const [];
  final Map<String, Lease> leasesById = {};
  BillingInfo? billingInfo;

  StreamSubscription<PoolUpdate>? _poolSub;
  StreamSubscription<LeaseUpdate>? _leaseSub;
  bool _started = false;

  ControlPlaneController(this._client);

  Future<void> start() async {
    if (_started) return;
    _started = true;

    try {
      await _client.connect();
      _poolSub = _client.poolUpdates.listen((update) {
        if (update.isFull) {
          poolNodes = List<PoolNode>.unmodifiable(update.nodes);
          notifyListeners();
        }
      });
      _leaseSub = _client.leaseUpdates.listen((update) {
        leasesById[update.lease.leaseId] = update.lease;
        notifyListeners();
      });
    } catch (e) {
      debugPrint('ControlPlaneController start error: $e');
      _started = false;
    }
  }

  Future<void> stop() async {
    _started = false;
    await _poolSub?.cancel();
    await _leaseSub?.cancel();
    _poolSub = null;
    _leaseSub = null;
    await _client.disconnect();
  }

  Future<void> refreshPool({
    String? region,
    String? gpuTier,
    NodeStatus? status,
  }) async {
    poolNodes = List<PoolNode>.unmodifiable(await _client.fetchPoolNodes(
      region: region,
      gpuTier: gpuTier,
      status: status,
    ));
    notifyListeners();
  }

  Future<List<Lease>> refreshLeases() async {
    final leases = await _client.fetchLeases();
    leasesById
      ..clear()
      ..addEntries(leases.map((lease) => MapEntry(lease.leaseId, lease)));
    notifyListeners();
    return leases;
  }

  Future<RentResult> rent({
    required String region,
    required String gpuTier,
    required BillingUnit billingUnit,
    int count = 1,
    String? clientRequestId,
  }) async {
    final result = await _client.rent(
      region: region,
      gpuTier: gpuTier,
      billingUnit: billingUnit,
      count: count,
      clientRequestId: clientRequestId,
    );
    for (final lease in result.leases) {
      leasesById[lease.leaseId] = lease;
    }
    notifyListeners();
    return result;
  }

  Future<List<Lease>> release({
    required List<String> leaseIds,
    String? clientRequestId,
  }) async {
    final leases = await _client.release(
      leaseIds: leaseIds,
      clientRequestId: clientRequestId,
    );
    for (final lease in leases) {
      leasesById[lease.leaseId] = lease;
    }
    notifyListeners();
    return leases;
  }

  Future<BillingInfo> refreshBilling() async {
    billingInfo = await _client.fetchBillingInfo();
    notifyListeners();
    return billingInfo!;
  }

  Future<void> requestRemoteControlLease({
    required String leaseId,
    required Map<String, dynamic> settings,
  }) async {
    await _client.requestRemoteControlLease(leaseId: leaseId, settings: settings);
  }

  @override
  void dispose() {
    _poolSub?.cancel();
    _leaseSub?.cancel();
    _client.dispose();
    super.dispose();
  }
}
