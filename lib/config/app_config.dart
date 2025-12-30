import 'package:flutter/foundation.dart';
import '../control_plane/node_agent_config.dart';

class AppConfig {
  static const String _envBaseUrl =
      String.fromEnvironment('CPP_API_BASE_URL', defaultValue: 'http://8.210.183.180:18080');

  static String get apiBaseUrl {
    if (NodeAgentConfig.apiUrl.isNotEmpty) {
      return NodeAgentConfig.apiUrl;
    }
    return _envBaseUrl;
  }

  static String get wsBaseUrl {
    final uri = Uri.parse(apiBaseUrl);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return uri.replace(scheme: scheme).toString();
  }

  static bool get isLocalServer {
    return apiBaseUrl.contains('127.0.0.1') ||
        apiBaseUrl.contains('10.0.2.2') ||
        apiBaseUrl.contains('localhost');
  }
}
