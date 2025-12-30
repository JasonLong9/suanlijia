import 'dart:async';

import '../service_locator.dart';
import '../services/node_agent_service.dart';
import '../base/logging.dart';
import 'node_agent_config.dart';

/// Headless node agent that runs without any GUI.
/// This is used when SLC.exe is started with --headless flag on Windows.
class HeadlessNodeAgent {
  Timer? _heartbeatTimer;
  final Completer<void> _shutdownCompleter = Completer<void>();

  /// Start the headless node agent.
  Future<void> start() async {
    VLOG0('[HeadlessNodeAgent] Starting...');
    VLOG0('[HeadlessNodeAgent] Device ID: ${NodeAgentConfig.deviceId}');
    VLOG0('[HeadlessNodeAgent] Region: ${NodeAgentConfig.region}');
    VLOG0('[HeadlessNodeAgent] GPU Tier: ${NodeAgentConfig.gpuTier}');

    // Initialize Node Agent Service
    await getIt<NodeAgentService>().init();
    VLOG0('[HeadlessNodeAgent] Node agent service initialized');

    // Start heartbeat timer
    final heartbeatSeconds = NodeAgentConfig.heartbeatSeconds;
    _heartbeatTimer = Timer.periodic(
      Duration(seconds: heartbeatSeconds),
      _onHeartbeat,
    );
    VLOG0('[HeadlessNodeAgent] Heartbeat timer started (${heartbeatSeconds}s interval)');

    VLOG0('[HeadlessNodeAgent] Node agent started successfully');
  }

  void _onHeartbeat(Timer timer) {
    final nodeService = getIt<NodeAgentService>();
    VLOG0('[HeadlessNodeAgent] Heartbeat - Connected: ${nodeService.isConnected}, ActiveLease: ${nodeService.activeLeaseId ?? "none"}');
    // The NodeAgentService handles heartbeat internally
  }

  /// Stop the headless node agent.
  Future<void> stop() async {
    VLOG0('[HeadlessNodeAgent] Stopping...');

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    if (!_shutdownCompleter.isCompleted) {
      _shutdownCompleter.complete();
    }

    VLOG0('[HeadlessNodeAgent] Stopped');
  }

  /// Run forever until process is terminated by Windows Service Manager.
  /// On Windows, the service wrapper (SLCSvc.exe) handles process termination.
  Future<void> runForever() async {
    VLOG0('[HeadlessNodeAgent] Running in background (Windows service mode)...');
    await _shutdownCompleter.future;
    VLOG0('[HeadlessNodeAgent] Shutdown complete');
  }
}
