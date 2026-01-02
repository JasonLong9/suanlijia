import 'dart:convert';

enum BillingUnit { minute, hour, day, week, month }

BillingUnit billingUnitFromWire(String value) {
  final normalized = value.trim().toLowerCase();
  return BillingUnit.values.firstWhere(
    (e) => e.name == normalized,
    orElse: () => BillingUnit.minute,
  );
}

String billingUnitToWire(BillingUnit value) => value.name;

enum NodeStatus {
  unknown,
  offline,
  free,
  assigned,
  inUse,
  releasing,
  disabled,
  maintenance,
}

NodeStatus nodeStatusFromWire(String value) {
  final normalized = value.trim().toUpperCase();
  switch (normalized) {
    case 'OFFLINE':
      return NodeStatus.offline;
    case 'FREE':
      return NodeStatus.free;
    case 'ASSIGNED':
      return NodeStatus.assigned;
    case 'IN_USE':
      return NodeStatus.inUse;
    case 'RELEASING':
      return NodeStatus.releasing;
    case 'DISABLED':
      return NodeStatus.disabled;
    case 'MAINTENANCE':
      return NodeStatus.maintenance;
    default:
      return NodeStatus.unknown;
  }
}

String nodeStatusToWire(NodeStatus value) {
  switch (value) {
    case NodeStatus.offline:
      return 'OFFLINE';
    case NodeStatus.free:
      return 'FREE';
    case NodeStatus.assigned:
      return 'ASSIGNED';
    case NodeStatus.inUse:
      return 'IN_USE';
    case NodeStatus.releasing:
      return 'RELEASING';
    case NodeStatus.disabled:
      return 'DISABLED';
    case NodeStatus.maintenance:
      return 'MAINTENANCE';
    case NodeStatus.unknown:
      return 'UNKNOWN';
  }
}

enum LeaseStatus {
  unknown,
  pending,
  assigned,
  ready,
  active,
  releasing,
  ended,
}

LeaseStatus leaseStatusFromWire(String value) {
  final normalized = value.trim().toUpperCase();
  switch (normalized) {
    case 'PENDING':
      return LeaseStatus.pending;
    case 'ASSIGNED':
      return LeaseStatus.assigned;
    case 'READY':
      return LeaseStatus.ready;
    case 'ACTIVE':
      return LeaseStatus.active;
    case 'RELEASING':
      return LeaseStatus.releasing;
    case 'ENDED':
      return LeaseStatus.ended;
    default:
      return LeaseStatus.unknown;
  }
}

String leaseStatusToWire(LeaseStatus value) {
  switch (value) {
    case LeaseStatus.pending:
      return 'PENDING';
    case LeaseStatus.assigned:
      return 'ASSIGNED';
    case LeaseStatus.ready:
      return 'READY';
    case LeaseStatus.active:
      return 'ACTIVE';
    case LeaseStatus.releasing:
      return 'RELEASING';
    case LeaseStatus.ended:
      return 'ENDED';
    case LeaseStatus.unknown:
      return 'UNKNOWN';
  }
}

enum EndReason {
  unknown,
  userRelease,
  nodeOffline,
  adminForceRelease,
  timeout,
  error
}

EndReason endReasonFromWire(String value) {
  final normalized = value.trim().toUpperCase();
  switch (normalized) {
    case 'USER_RELEASE':
      return EndReason.userRelease;
    case 'NODE_OFFLINE':
      return EndReason.nodeOffline;
    case 'ADMIN_FORCE_RELEASE':
      return EndReason.adminForceRelease;
    case 'TIMEOUT':
      return EndReason.timeout;
    case 'ERROR':
      return EndReason.error;
    default:
      return EndReason.unknown;
  }
}

String endReasonToWire(EndReason value) {
  switch (value) {
    case EndReason.userRelease:
      return 'USER_RELEASE';
    case EndReason.nodeOffline:
      return 'NODE_OFFLINE';
    case EndReason.adminForceRelease:
      return 'ADMIN_FORCE_RELEASE';
    case EndReason.timeout:
      return 'TIMEOUT';
    case EndReason.error:
      return 'ERROR';
    case EndReason.unknown:
      return 'UNKNOWN';
  }
}

class PoolNode {
  final String deviceId;
  final String region;
  final String gpuTier;
  final NodeStatus status;
  final DateTime lastSeen;
  final String? connectionId;
  final String? agentVersion;
  final Map<String, dynamic>? capabilities;

  const PoolNode({
    required this.deviceId,
    required this.region,
    required this.gpuTier,
    required this.status,
    required this.lastSeen,
    this.connectionId,
    this.agentVersion,
    this.capabilities,
  });

  PoolNode copyWith({
    String? deviceId,
    String? region,
    String? gpuTier,
    NodeStatus? status,
    DateTime? lastSeen,
    String? connectionId,
    String? agentVersion,
    Map<String, dynamic>? capabilities,
  }) {
    return PoolNode(
      deviceId: deviceId ?? this.deviceId,
      region: region ?? this.region,
      gpuTier: gpuTier ?? this.gpuTier,
      status: status ?? this.status,
      lastSeen: lastSeen ?? this.lastSeen,
      connectionId: connectionId ?? this.connectionId,
      agentVersion: agentVersion ?? this.agentVersion,
      capabilities: capabilities ?? this.capabilities,
    );
  }

  factory PoolNode.fromJson(Map<String, dynamic> json) {
    return PoolNode(
      deviceId: json['device_id'] as String,
      region: json['region'] as String,
      gpuTier: json['gpu_tier'] as String,
      status: nodeStatusFromWire((json['status'] ?? 'UNKNOWN') as String),
      lastSeen: DateTime.parse(json['last_seen'] as String),
      connectionId: json['connection_id'] as String?,
      agentVersion: json['agent_version'] as String?,
      capabilities: json['capabilities'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'device_id': deviceId,
      'connection_id': connectionId,
      'region': region,
      'gpu_tier': gpuTier,
      'status': nodeStatusToWire(status),
      'last_seen': lastSeen.toUtc().toIso8601String(),
      'agent_version': agentVersion,
      'capabilities': capabilities,
    };
  }
}

class PricePlan {
  final String region;
  final String gpuTier;
  final BillingUnit billingUnit;
  final double unitPrice;

  const PricePlan({
    required this.region,
    required this.gpuTier,
    required this.billingUnit,
    required this.unitPrice,
  });

  factory PricePlan.fromJson(Map<String, dynamic> json) {
    return PricePlan(
      region: json['region'] as String,
      gpuTier: json['gpu_tier'] as String,
      billingUnit: billingUnitFromWire(json['billing_unit'] as String),
      unitPrice: (json['unit_price'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'region': region,
      'gpu_tier': gpuTier,
      'billing_unit': billingUnitToWire(billingUnit),
      'unit_price': unitPrice,
    };
  }
}

class Lease {
  final String leaseId;
  final String deviceId;
  final LeaseStatus status;
  final BillingUnit billingUnit;
  final double? unitPrice;
  final int? billedUnits;
  final double? amount;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final EndReason? endReason;
  final String? leaseToken;

  const Lease({
    required this.leaseId,
    required this.deviceId,
    required this.status,
    required this.billingUnit,
    this.unitPrice,
    this.billedUnits,
    this.amount,
    this.startedAt,
    this.endedAt,
    this.endReason,
    this.leaseToken,
  });

  Lease copyWith({
    String? leaseId,
    String? deviceId,
    LeaseStatus? status,
    BillingUnit? billingUnit,
    double? unitPrice,
    int? billedUnits,
    double? amount,
    DateTime? startedAt,
    DateTime? endedAt,
    EndReason? endReason,
    String? leaseToken,
  }) {
    return Lease(
      leaseId: leaseId ?? this.leaseId,
      deviceId: deviceId ?? this.deviceId,
      status: status ?? this.status,
      billingUnit: billingUnit ?? this.billingUnit,
      unitPrice: unitPrice ?? this.unitPrice,
      billedUnits: billedUnits ?? this.billedUnits,
      amount: amount ?? this.amount,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      endReason: endReason ?? this.endReason,
      leaseToken: leaseToken ?? this.leaseToken,
    );
  }

  factory Lease.fromJson(Map<String, dynamic> json) {
    return Lease(
      leaseId: json['lease_id'] as String,
      deviceId: json['device_id'] as String,
      status: leaseStatusFromWire((json['status'] ?? 'UNKNOWN') as String),
      billingUnit: billingUnitFromWire(json['billing_unit'] as String),
      unitPrice: (json['unit_price'] as num?)?.toDouble(),
      billedUnits: json['billed_units'] as int?,
      amount: (json['amount'] as num?)?.toDouble(),
      startedAt: json['started_at'] == null
          ? null
          : DateTime.parse(json['started_at'] as String),
      endedAt: json['ended_at'] == null
          ? null
          : DateTime.parse(json['ended_at'] as String),
      endReason: json['end_reason'] == null
          ? null
          : endReasonFromWire(json['end_reason'] as String),
      leaseToken: json['lease_token'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lease_id': leaseId,
      'device_id': deviceId,
      'status': leaseStatusToWire(status),
      'billing_unit': billingUnitToWire(billingUnit),
      'unit_price': unitPrice,
      'billed_units': billedUnits,
      'amount': amount,
      'started_at': startedAt?.toUtc().toIso8601String(),
      'ended_at': endedAt?.toUtc().toIso8601String(),
      'end_reason': endReason == null ? null : endReasonToWire(endReason!),
      'lease_token': leaseToken,
    };
  }
}

class BillingRecord {
  final String recordId;
  final String leaseId;
  final double amount;
  final int billedUnits;
  final BillingUnit billingUnit;
  final DateTime createdAt;
  final EndReason? endReason;

  const BillingRecord({
    required this.recordId,
    required this.leaseId,
    required this.amount,
    required this.billedUnits,
    required this.billingUnit,
    required this.createdAt,
    this.endReason,
  });

  factory BillingRecord.fromJson(Map<String, dynamic> json) {
    return BillingRecord(
      recordId: json['record_id'] as String,
      leaseId: json['lease_id'] as String,
      amount: (json['amount'] as num).toDouble(),
      billedUnits: json['billed_units'] as int,
      billingUnit: billingUnitFromWire(json['billing_unit'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      endReason: json['end_reason'] == null
          ? null
          : endReasonFromWire(json['end_reason'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'record_id': recordId,
      'lease_id': leaseId,
      'amount': amount,
      'billed_units': billedUnits,
      'billing_unit': billingUnitToWire(billingUnit),
      'created_at': createdAt.toUtc().toIso8601String(),
      'end_reason': endReason == null ? null : endReasonToWire(endReason!),
    };
  }
}

class BillingInfo {
  final String currency;
  final double balance;
  final List<Lease> activeLeases;
  final List<BillingRecord> history;

  const BillingInfo({
    required this.currency,
    required this.balance,
    required this.activeLeases,
    required this.history,
  });

  factory BillingInfo.fromJson(Map<String, dynamic> json) {
    return BillingInfo(
      currency: json['currency'] as String,
      balance: (json['balance'] as num).toDouble(),
      activeLeases: (json['active_leases'] as List<dynamic>)
          .map((e) => Lease.fromJson(e as Map<String, dynamic>))
          .toList(),
      history: (json['history'] as List<dynamic>)
          .map((e) => BillingRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class PoolUpdate {
  final bool isFull;
  final List<PoolNode> nodes;

  const PoolUpdate({required this.isFull, required this.nodes});
}

class LeaseUpdate {
  final Lease lease;

  const LeaseUpdate(this.lease);
}

class RentResult {
  final List<Lease> leases;
  final Map<String, String> leaseTokenByLeaseId;

  const RentResult({required this.leases, required this.leaseTokenByLeaseId});
}

class ControlPlaneApiException implements Exception {
  final String code;
  final String message;
  final Object? details;

  const ControlPlaneApiException({
    required this.code,
    required this.message,
    this.details,
  });

  @override
  String toString() {
    final detailsText =
        details == null ? '' : ' details=${jsonEncode(details)}';
    return 'ControlPlaneApiException(code=$code, message=$message$detailsText)';
  }
}
