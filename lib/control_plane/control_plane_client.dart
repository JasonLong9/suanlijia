import 'control_plane_models.dart';

abstract class ControlPlaneClient {
  Stream<PoolUpdate> get poolUpdates;
  Stream<LeaseUpdate> get leaseUpdates;

  Future<void> connect();
  Future<void> disconnect();

  Future<List<PoolNode>> fetchPoolNodes({
    String? region,
    String? gpuTier,
    NodeStatus? status,
  });

  Future<RentResult> rent({
    required String region,
    required String gpuTier,
    required BillingUnit billingUnit,
    int count = 1,
    String? clientRequestId,
  });

  Future<List<Lease>> release({
    required List<String> leaseIds,
    String? clientRequestId,
  });

  Future<BillingInfo> fetchBillingInfo();

  Future<void> requestRemoteControlLease({
    required String leaseId,
    required Map<String, dynamic> settings,
  });

  void dispose();
}
