import 'dart:async';

import 'package:flutter/material.dart';

import '../control_plane/node_agent_config.dart';
import '../service_locator.dart';
import '../services/app_info_service.dart';
import '../services/websocket_service.dart';
import '../services/node_agent_service.dart';

class NodeModePage extends StatefulWidget {
  const NodeModePage({super.key});

  @override
  State<NodeModePage> createState() => _NodeModePageState();
}

class _NodeModePageState extends State<NodeModePage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nodeAgent = getIt<NodeAgentService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Node Mode'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _kv('CPP_DEVICE_ID', NodeAgentConfig.deviceId),
          _kv('CPP_REGION', NodeAgentConfig.region),
          _kv('CPP_GPU_TIER', NodeAgentConfig.gpuTier),
          const SizedBox(height: 12),
          _kv('Node WS', nodeAgent.isConnected ? 'connected' : 'disconnected'),
          _kv('Legacy WS', WebSocketService.connectionState.name),
          const SizedBox(height: 12),
          _kv('Active Lease', nodeAgent.activeLeaseId ?? '-'),
          const SizedBox(height: 24),
          const Text(
            '说明：该节点通过 device token 连接后端；收到 remoteSessionRequested 后会启动串流并发送 offer。',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              k,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(v.isEmpty ? '-' : v)),
        ],
      ),
    );
  }
}
