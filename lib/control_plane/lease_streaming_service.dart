import '../entities/device.dart';
import '../global_settings/streaming_settings.dart';
import '../services/streaming_manager.dart';
import 'control_plane_models.dart';

class LeaseStreamingService {
  final StreamingManager _streamingManager;

  LeaseStreamingService(this._streamingManager);

  Device? startRemoteControl({
    required Lease lease,
    required String leaseToken,
  }) {
    final token = leaseToken.isNotEmpty ? leaseToken : (lease.leaseToken ?? '');
    if (token.isEmpty) return null;

    StreamingSettings.connectPassword = token;

    final existing = StreamingManager.sessions[lease.deviceId];
    if (existing != null) {
      return existing.controlled;
    }

    final target = Device(
      uid: 0,
      nickname: 'GPU Node',
      devicename: lease.deviceId,
      devicetype: 'Windows',
      websocketSessionid: lease.deviceId,
      connective: true,
      screencount: 1,
    );
    StreamingManager.startStreaming(target, leaseId: lease.leaseId);
    return target;
  }
}
