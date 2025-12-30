import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:universal_io/io.dart';

class NodeAgentConfig {
  static bool isHeadless = false;

  static const bool _envEnabled =
      bool.fromEnvironment('CPP_NODE_MODE', defaultValue: false);
  static const String _envDeviceId =
      String.fromEnvironment('CPP_DEVICE_ID', defaultValue: '');
  static const String _envDeviceSecret =
      String.fromEnvironment('CPP_DEVICE_SECRET', defaultValue: '');
  static const String _envRegion =
      String.fromEnvironment('CPP_REGION', defaultValue: '');
  static const String _envGpuTier =
      String.fromEnvironment('CPP_GPU_TIER', defaultValue: '');
  static const int _envHeartbeatSeconds = int.fromEnvironment(
    'CPP_NODE_HEARTBEAT_SECONDS',
    defaultValue: 10,
  );
  static const String _envAgentVersion =
      String.fromEnvironment('CPP_NODE_AGENT_VERSION', defaultValue: '');

  static _NodeAgentRuntimeConfig? _runtimeCache;
  static _NodeAgentRuntimeConfig get _runtime {
    _runtimeCache ??= _NodeAgentRuntimeConfig.load();
    return _runtimeCache!;
  }

  static bool get enabled => _envEnabled || _runtime.enabled;

  static String get deviceId =>
      _envDeviceId.isNotEmpty ? _envDeviceId : _runtime.deviceId;

  static String get deviceSecret =>
      _envDeviceSecret.isNotEmpty ? _envDeviceSecret : _runtime.deviceSecret;

  static String get region {
    final v = _envRegion.isNotEmpty ? _envRegion : _runtime.region;
    return v.isNotEmpty ? v : 'unknown';
  }

  static String get gpuTier {
    final v = _envGpuTier.isNotEmpty ? _envGpuTier : _runtime.gpuTier;
    return v.isNotEmpty ? v : 'unknown';
  }

  static int get heartbeatSeconds => _runtime.heartbeatSeconds > 0
      ? _runtime.heartbeatSeconds
      : _envHeartbeatSeconds;

  static String get agentVersion {
    final v =
        _envAgentVersion.isNotEmpty ? _envAgentVersion : _runtime.agentVersion;
    return v.isNotEmpty ? v : '0.10.0';
  }

  static String get city => _runtime.city;

  static String get apiUrl => _runtime.apiUrl;

  static bool get rebootOnRelease => _runtime.rebootOnRelease;

  static int get rebootDelaySeconds =>
      _runtime.rebootDelaySeconds >= 0 ? _runtime.rebootDelaySeconds : 3;
}

class _NodeAgentRuntimeConfig {
  final bool enabled;
  final String deviceId;
  final String deviceSecret;
  final String region;
  final String gpuTier;
  final int heartbeatSeconds;
  final String agentVersion;
  final String city;
  final String apiUrl;
  final bool rebootOnRelease;
  final int rebootDelaySeconds;

  const _NodeAgentRuntimeConfig({
    required this.enabled,
    required this.deviceId,
    required this.deviceSecret,
    required this.region,
    required this.gpuTier,
    required this.heartbeatSeconds,
    required this.agentVersion,
    required this.city,
    required this.apiUrl,
    required this.rebootOnRelease,
    required this.rebootDelaySeconds,
  });

  static const _NodeAgentRuntimeConfig _disabled = _NodeAgentRuntimeConfig(
    enabled: false,
    deviceId: '',
    deviceSecret: '',
    region: '',
    gpuTier: '',
    heartbeatSeconds: 0,
    agentVersion: '',
    city: '',
    apiUrl: '',
    rebootOnRelease: true,
    rebootDelaySeconds: 3,
  );

  static _NodeAgentRuntimeConfig load() {
    _writeEarlyLog('load() called');
    if (kIsWeb) {
      _writeEarlyLog('load(): skipped - kIsWeb');
      return _disabled;
    }
    if (!Platform.isWindows) {
      _writeEarlyLog('load(): skipped - not Windows');
      return _disabled;
    }

    final base = Platform.environment['PROGRAMDATA'] ?? r'C:\ProgramData';
    final path = '$base\\SLC\\node.json';
    _writeEarlyLog('load(): path=$path');

    try {
      final file = File(path);
      if (!file.existsSync()) {
        _writeEarlyLog('load(): file not found');
        return _disabled;
      }
      final text = file.readAsStringSync();
      _writeEarlyLog('load(): file read, length=${text.length}');
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        _writeEarlyLog('load(): invalid JSON format');
        return _disabled;
      }

      bool readBool(String key, bool fallback) {
        final v = decoded[key];
        if (v is bool) return v;
        if (v is num) return v != 0;
        if (v is String) {
          final s = v.trim().toLowerCase();
          if (s == 'true' || s == '1' || s == 'yes' || s == 'y') return true;
          if (s == 'false' || s == '0' || s == 'no' || s == 'n') return false;
        }
        return fallback;
      }

      int readInt(String key, int fallback) {
        final v = decoded[key];
        if (v is int) return v;
        if (v is num) return v.toInt();
        if (v is String) return int.tryParse(v.trim()) ?? fallback;
        return fallback;
      }

      String readString(String key, String fallback) {
        final v = decoded[key];
        if (v is String) return v;
        return fallback;
      }

      final config = _NodeAgentRuntimeConfig(
        enabled: readBool('enabled', false),
        deviceId: readString('device_id', ''),
        deviceSecret: readString('device_secret', ''),
        region: readString('region', ''),
        gpuTier: readString('gpu_tier', ''),
        heartbeatSeconds: readInt('heartbeat_seconds', 10),
        agentVersion: readString('agent_version', '0.10.0'),
        city: readString('city', ''),
        apiUrl: readString('api_url', ''),
        rebootOnRelease: readBool('reboot_on_release', true),
        rebootDelaySeconds: readInt('reboot_delay_seconds', 3),
      );
      _writeEarlyLog(
          'load(): success, enabled=${config.enabled}, deviceId=${config.deviceId}');
      return config;
    } catch (e, stack) {
      _writeEarlyLog('load(): ERROR: $e\n$stack');
      return _disabled;
    }
  }

  /// 早期日志 - 不依赖任何初始化
  static void _writeEarlyLog(String msg) {
    try {
      final logDir = Directory(r'C:\ProgramData\SLC\logs');
      if (!logDir.existsSync()) logDir.createSync(recursive: true);
      final logFile = File('${logDir.path}\\config_load.log');
      logFile.writeAsStringSync(
        '[${DateTime.now().toIso8601String()}] $msg\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }
}
