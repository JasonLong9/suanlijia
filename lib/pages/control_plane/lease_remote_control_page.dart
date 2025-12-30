import 'package:flutter/material.dart';

import '../../control_plane/control_plane_controller.dart';
import '../../control_plane/control_plane_models.dart';
import '../../control_plane/lease_streaming_service.dart';
import '../../controller/screen_controller.dart';
import '../../entities/device.dart';
import '../../entities/session.dart';
import '../../services/streaming_manager.dart';
import '../../services/webrtc_service.dart';
import '../../service_locator.dart';
import '../../utils/widgets/global_remote_screen_renderer.dart';

class LeaseRemoteControlPage extends StatefulWidget {
  final Lease lease;

  const LeaseRemoteControlPage({super.key, required this.lease});

  @override
  State<LeaseRemoteControlPage> createState() => _LeaseRemoteControlPageState();
}

class _LeaseRemoteControlPageState extends State<LeaseRemoteControlPage> {
  Device? _device;
  String? _error;

  @override
  void initState() {
    super.initState();
    ScreenController.setOnlyShowRemoteScreen(true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    ScreenController.setOnlyShowRemoteScreen(false);
    final device = _device;
    if (device != null) {
      getIt<StreamingManager>().stopStreaming(device);
    }
    super.dispose();
  }

  Future<void> _start() async {
    final device = getIt<LeaseStreamingService>().startRemoteControl(
      lease: widget.lease,
      leaseToken: widget.lease.leaseToken ?? '',
    );
    if (device == null) {
      setState(() => _error = '缺少 lease_token，无法进入远�?);
      return;
    }

    WebrtcService.updateCurrentRenderingDevice(device.websocketSessionid, () {});
    setState(() => _device = device);
  }

  Future<void> _release() async {
    try {
      await getIt<ControlPlaneController>()
          .release(leaseIds: [widget.lease.leaseId]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已释放：已停止计费并触发节点重启')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('释放失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = _device;
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('远控')),
        body: Center(child: Text(_error!)),
      );
    }
    if (device == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return ValueListenableBuilder<StreamingSessionConnectionState>(
      valueListenable: device.connectionState,
      builder: (context, state, child) {
        if (state != StreamingSessionConnectionState.connected) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('正在连接...'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text('状�? ${state.name}'),
                  const SizedBox(height: 24),
                  OutlinedButton(
                    onPressed: () {
                      getIt<StreamingManager>().stopStreaming(device);
                      Navigator.pop(context);
                    },
                    child: const Text('取消连接'),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          body: Stack(
            children: [
              const GlobalRemoteScreenRenderer(),
              SafeArea(
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      color: Colors.white,
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: () {
                        getIt<StreamingManager>().stopStreaming(device);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('已断开连接（租赁仍在计费，需“释放资源”才停止计费�?),
                          ),
                        );
                      },
                      child: const Text('断开连接'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('确认释放'),
                            content:
                                const Text('释放后将立即停止计费，并通知节点重启。确定要释放吗？'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('取消'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('确认释放'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          getIt<StreamingManager>().stopStreaming(device);
                          await _release();
                        }
                      },
                      child: const Text('释放资源'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

