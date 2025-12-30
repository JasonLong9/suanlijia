import 'dart:async';
import 'dart:convert';

import 'package:slc/config/app_config.dart';
import 'package:slc/control_plane/node_agent_config.dart';
import 'package:slc/base/constants.dart';
import 'package:slc/global_settings/streaming_settings.dart';
import 'package:slc/services/app_info_service.dart';
import 'package:slc/services/login_service.dart';
import 'package:slc/services/shared_preferences_manager.dart';
import 'package:slc/services/streamed_manager.dart';
import 'package:slc/utils/hash_util.dart';
import 'package:slc/utils/websocket.dart'
    if (dart.library.js) '../utils/websocket_web.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:universal_io/io.dart';
import 'dart:io' as java_io;

import '../base/logging.dart';
import '../entities/user.dart';
import '../entities/device.dart';
import '../utils/system_tray_manager.dart';

class NodeAgentService {
  static NodeAgentService? instance;
  final LoginService _loginService;
  
  NodeAgentService(this._loginService) {
    instance = this;
  }

  SimpleWebSocket? _socket;
  String _baseUrl = '';
  Timer? _nodeHeartbeatTimer;
  Timer? _reconnectTimer;
  String? _activeLeaseId;
  String? _activeLeaseToken;
  bool _reportedServiceWrapperLog = false;
  bool should_be_connected = false;
  bool _wsOpen = false;
  
  static const JsonEncoder _encoder = JsonEncoder();
  static const JsonDecoder _decoder = JsonDecoder();

  bool get isConnected => _wsOpen;
  String? get activeLeaseId => _activeLeaseId;

  /// 发送远程日志到服务器（用于崩溃前诊断）
  static Future<void> remoteLog(String level, String message, [Map<String, dynamic>? context]) async {
    try {
      String baseUrl = LoginService.baseUrl;
      if (NodeAgentConfig.enabled && NodeAgentConfig.apiUrl.isNotEmpty) {
        baseUrl = NodeAgentConfig.apiUrl;
      }
      final url = '$baseUrl/api/client/log/';
      final deviceId = NodeAgentConfig.deviceId.isNotEmpty 
          ? NodeAgentConfig.deviceId 
          : 'unknown';
      
      await http.post(
        Uri.parse(url),
        headers: const {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({
          'device_id': deviceId,
          'level': level,
          'message': message,
          'timestamp': DateTime.now().toIso8601String(),
          'context': context,
        }),
      ).timeout(const Duration(seconds: 2));
    } catch (_) {
      // 忽略日志发送失败
    }
  }

  void _debugLog(String msg) {
    try {
      final file = java_io.File(r'C:\ProgramData\SLC\logs\startup.log');
      final timestamp = DateTime.now().toIso8601String();
      file.writeAsStringSync('[$timestamp] [WS_DEBUG] $msg\n',
          mode: java_io.FileMode.append, flush: true);
    } catch (_) {}
    // Also send to server for remote diagnostics (best-effort).
    unawaited(remoteLog('DEBUG', '[WS_DEBUG] $msg'));
  }

  void _reportServiceWrapperLogOnce() {
    if (_reportedServiceWrapperLog) return;
    _reportedServiceWrapperLog = true;
    if (kIsWeb || !Platform.isWindows) return;
    try {
      final file = java_io.File(r'C:\ProgramData\SLC\logs\slcsvc.log');
      if (!file.existsSync()) return;
      const maxBytes = 64 * 1024;
      const maxLines = 40;
      final raf = file.openSync(mode: java_io.FileMode.read);
      try {
        final length = raf.lengthSync();
        final start = length > maxBytes ? (length - maxBytes) : 0;
        raf.setPositionSync(start);
        final bytes = raf.readSync(length - start);
        final text = utf8.decode(bytes, allowMalformed: true);
        final parts = text.split(RegExp(r'\r?\n'));
        final lines =
            (start > 0 && parts.isNotEmpty) ? parts.sublist(1) : parts;
        final trimmed = lines.map((l) => l.trim()).where((l) => l.isNotEmpty);
        final list = trimmed.toList();
        final tail =
            list.length > maxLines ? list.sublist(list.length - maxLines) : list;
        unawaited(remoteLog('INFO', '[slcsvc] tail', {
          'lines': tail,
        }));
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      // ignore
    }
  }

  String _buildWsBaseUrlFromHttpBase(String httpUrl) {
    var url = httpUrl.trim();
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.startsWith('https://')) {
      return 'wss://${url.substring(8)}/ws/';
    } else if (url.startsWith('http://')) {
      return 'ws://${url.substring(7)}/ws/';
    }
    return url;
  }

  Future<void> init() async {
    _debugLog('NodeAgentService.init: starting');
    VLOG0('NodeAgentService.init: starting');
    VLOG0('NodeAgentService.init: deviceId=${NodeAgentConfig.deviceId}');
    VLOG0('NodeAgentService.init: apiUrl=${NodeAgentConfig.apiUrl}');

    should_be_connected = true;
    _ensureUserInitialized();
    _reportServiceWrapperLogOnce();
    
    if (NodeAgentConfig.isHeadless) {
      _debugLog('NodeAgentService.init: skipping _clearLeaseState in headless mode');
      VLOG0('NodeAgentService.init: skipping _clearLeaseState in headless mode');
    } else {
      await _clearLeaseState(stopSessions: true);
    }

    if (NodeAgentConfig.deviceId.isEmpty ||
        NodeAgentConfig.deviceSecret.isEmpty) {
      _debugLog('NodeMode: missing CPP_DEVICE_ID/CPP_DEVICE_SECRET, skip connect');
      VLOG0('NodeMode: missing CPP_DEVICE_ID/CPP_DEVICE_SECRET, skip connect');
      return;
    }

    if (NodeAgentConfig.enabled && NodeAgentConfig.apiUrl.isNotEmpty) {
      _debugLog('NodeMode: using custom apiUrl: ${NodeAgentConfig.apiUrl}');
      _baseUrl = _buildWsBaseUrlFromHttpBase(NodeAgentConfig.apiUrl);
    } else {
      _baseUrl = _buildWsBaseUrlFromHttpBase(AppConfig.apiBaseUrl);
    }
    VLOG0('NodeAgentService.init: wsBaseUrl=$_baseUrl');
    _debugLog('NodeAgentService.init: fetching device token...');
    final deviceToken = await _fetchDeviceToken(
      deviceId: NodeAgentConfig.deviceId,
      deviceSecret: NodeAgentConfig.deviceSecret,
    );
    _debugLog(
        'NodeAgentService.init: deviceToken=${deviceToken != null ? "obtained" : "failed"}');
    VLOG0(
        'NodeAgentService.init: deviceToken=${deviceToken != null ? "obtained" : "failed"}');
    if (deviceToken == null || deviceToken.isEmpty) {
      _debugLog('NodeMode: failed to fetch device token');
      VLOG0('NodeMode: failed to fetch device token');
      return;
    }

    var url = '$_baseUrl?token=$deviceToken';
    _socket = SimpleWebSocket(url);
    _wsOpen = false;

    _socket?.onOpen = () {
      _wsOpen = true;
      _debugLog('WS: onOpen');
      _sendNodeHello();
      _startNodeHeartbeat();
    };

    _socket?.onMessage = (message) async {
      await onMessage(_decoder.convert(message));
    };

    _socket?.onClose = (code, message) async {
      _debugLog('WS: onClose ($code, $message)');
      _wsOpen = false;
      _socket = null;
      _stopNodeHeartbeat();
      if (NodeAgentConfig.isHeadless) {
        _debugLog('WS: onClose skipping _clearLeaseState in headless mode');
      } else {
        await _clearLeaseState(stopSessions: true);
      }
      
      if (should_be_connected) {
        _reconnectTimer?.cancel();
        _reconnectTimer =
            Timer.periodic(const Duration(seconds: 30), (Timer timer) async {
          if (isConnected) {
            timer.cancel();
            _reconnectTimer = null;
            return;
          }
          _debugLog('WS: attempting reconnect...');
          init();
        });
      }
      VLOG0('NodeAgent disconnected: $code $message');
    };

    _debugLog('NodeAgentService.init: calling socket.connect()');

    await _socket?.connect();
  }

  Future<void> disconnect() async {
    should_be_connected = false;
    _stopNodeHeartbeat();
    if (NodeAgentConfig.isHeadless) {
      VLOG0('NodeAgentService.disconnect: skipping _clearLeaseState in headless mode');
    } else {
      await _clearLeaseState(stopSessions: true);
    }
    _socket?.close();
    _socket = null;
    _wsOpen = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  Future<void> onMessage(Map<String, dynamic> mapData) async {
    var data = mapData['data'];
    final msgType = mapData['type'];
    VLOG0('[NodeAgentService] onMessage: type=$msgType');
    
    // v3.22: 增加远程日志以诊断消息处理
    unawaited(remoteLog('INFO', '[v3.22] onMessage: type=$msgType'));

    switch (msgType) {
      case 'connection_info':
        {
          VLOG0('[NodeAgentService] Received connection_info');
          AppStateService.lastwebsocketSessionid = AppStateService.websocketSessionid;
          AppStateService.websocketSessionid = data['connection_id'];
          
          // Update User and thisDevice for StreamingSession validation
          ApplicationInfo.user = User(uid: data['uid'], nickname: data['nickname']);
          ApplicationInfo.thisDevice = Device(
            uid: data['uid'],
            nickname: data['nickname'],
            devicename: NodeAgentConfig.deviceId,
            devicetype: 'Windows',
            websocketSessionid: AppStateService.websocketSessionid!,
            connective: true,
            screencount: ApplicationInfo.screenCount,
          );
          VLOG0('[NodeAgentService] Session ID initialized: ${AppStateService.websocketSessionid}');
        }
      case 'lease_assigned':
        {
          final payload =
              data is Map<String, dynamic> ? data : <String, dynamic>{};
          final leaseId = payload['lease_id'] as String?;
          final leaseToken = payload['lease_token'] as String?;
          if (leaseId == null || leaseToken == null) return;
          _activeLeaseId = leaseId;
          _activeLeaseToken = leaseToken;
          await _applyLeaseCredentials(leaseToken);
          send('lease_ready', {
            'lease_id': leaseId,
            'device_id': NodeAgentConfig.deviceId,
            'ts': DateTime.now().toUtc().toIso8601String(),
          });
        }
      case 'lease_release':
        {
          final payload =
              data is Map<String, dynamic> ? data : <String, dynamic>{};
          final leaseId = payload['lease_id'] as String?;
          if (leaseId != null && _activeLeaseId == leaseId) {
            _activeLeaseId = null;
          }
          _activeLeaseToken = null;
          if (NodeAgentConfig.isHeadless) {
            VLOG0('NodeAgentService.onMessage: lease_release skipping _clearLeaseState in headless mode');
          } else {
            await _clearLeaseState(stopSessions: true);
          }
          if (!kIsWeb && Platform.isWindows) {
             try {
               // HardwareSimulator.rebootSystem();
             } catch (e) {
               VLOG0('Reboot failed: $e');
             }
          }
        }
      // === WebRTC 信令消息处理 ===
      case 'remoteSessionRequested':
        {
          VLOG0('[NodeAgentService] Received remoteSessionRequested!');
          unawaited(remoteLog('INFO', '收到远程连接请求', {'requester': '云玩加网页端'}));
          final payload = data is Map ? data : const <String, dynamic>{};
          final requesterInfo = payload['requester_info'];
          final rawSettings = payload['settings'];
          if (requesterInfo != null && rawSettings is Map) {
            final settings = Map<String, dynamic>.from(rawSettings);

            // Lease node: some controllers may omit connectPassword in settings.
            final connectPassword = settings['connectPassword'];
            if ((connectPassword == null || (connectPassword is String && connectPassword.isEmpty)) &&
                _activeLeaseToken != null &&
                NodeAgentConfig.enabled) {
              settings['connectPassword'] = _activeLeaseToken!;
              VLOG0('[NodeAgentService] remoteSessionRequested: filled connectPassword from active lease token');
            }

            // Headless node (service) on headless GPUs often has no physical monitor.
            // Only default streamMode when the controller truly omitted it.
            // If controller explicitly sends streamMode=0 (default capture), respect it.
            final streamMode = settings['streamMode'];
            final isUnspecifiedStreamMode = streamMode == null;
            if (NodeAgentConfig.enabled &&
                NodeAgentConfig.isHeadless &&
                isUnspecifiedStreamMode) {
              settings['streamMode'] = VDISPLAY_OCCUPY;
              settings['targetScreenId'] ??= 0;
              settings['customScreenWidth'] ??= 1920;
              settings['customScreenHeight'] ??= 1080;
              VLOG0(
                  '[NodeAgentService] remoteSessionRequested: defaulted streamMode=VDISPLAY_OCCUPY (headless node, unspecified streamMode)');
            }

            // Ensure targetScreenId exists (some clients may omit it).
            settings['targetScreenId'] ??= 0;

            VLOG0('[NodeAgentService] Calling StreamedManager.startStreaming...');
            await StreamedManager.startStreaming(
                Device.fromJson(requesterInfo),
                StreamedSettings.fromJson(settings));
          } else {
            VLOG0('[NodeAgentService] remoteSessionRequested: missing requester_info or settings');
          }
        }
      case 'answer':
        {
          VLOG0('[NodeAgentService] Received answer');
          StreamedManager.onAnswerReceived(
              data['source_connectionid'], data['description']);
        }
      case 'candidate2':
        {
          VLOG0('[NodeAgentService] Received candidate2');
          StreamedManager.onCandidateReceived(
              data['source_connectionid'], data['candidate']);
        }
      case 'restartRequested':
        {
          VLOG0('[NodeAgentService] Received restartRequested');
          if (StreamingSettings.connectPasswordHash == HashUtil.hash(data['password'])) {
            VLOG0('[NodeAgentService] Password verified, restarting...');
            SystemTrayManager().restart();
          } else {
            VLOG0('[NodeAgentService] Restart rejected: password mismatch');
          }
        }
      default:
        VLOG0('[NodeAgentService] Unknown message type: $msgType');
        break;
    }
  }

  void send(String event, dynamic data) {
    final socket = _socket;
    if (!_wsOpen || socket == null) {
      if (event == 'offer' || event == 'answer') {
        VLOG0('[NodeAgentService] drop $event (ws not connected)');
      }
      return;
    }

    if (event == 'offer' && data is Map) {
      final target = data['target_connectionid'];
      final description = data['description'];
      final sdp = description is Map ? description['sdp'] : null;
      final targetStr = target is String
          ? (target.length > 8 ? '${target.substring(0, 8)}...' : target)
          : '$target';
      final sdpLen = sdp is String ? sdp.length : null;
      VLOG0('[NodeAgentService] send offer -> target=$targetStr sdpLen=$sdpLen');
    } else if (event == 'answer' && data is Map) {
      final target = data['target_connectionid'];
      final targetStr = target is String
          ? (target.length > 8 ? '${target.substring(0, 8)}...' : target)
          : '$target';
      VLOG0('[NodeAgentService] send answer -> target=$targetStr');
    }

    final request = {'type': event, 'data': data};
    socket.send(_encoder.convert(request));
  }

  Future<String?> _fetchDeviceToken({
    required String deviceId,
    required String deviceSecret,
  }) async {
    String baseUrl = LoginService.baseUrl;
    if (NodeAgentConfig.enabled && NodeAgentConfig.apiUrl.isNotEmpty) {
      baseUrl = NodeAgentConfig.apiUrl;
    }
    final url = '$baseUrl/api/device/token/';
    _debugLog('_fetchDeviceToken: POST $url');
    VLOG0('NodeAgentService._fetchDeviceToken: POST $url');
    try {
      final uri = Uri.parse(url);
      final response = await http.post(
        uri,
        headers: const {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({
          'device_id': deviceId,
          'device_secret': deviceSecret,
        }),
      );
      _debugLog('_fetchDeviceToken: status=${response.statusCode}');
      VLOG0('NodeAgentService._fetchDeviceToken: status=${response.statusCode}');
      if (response.statusCode != 200) {
        _debugLog('_fetchDeviceToken: error body=${response.body}');
        VLOG0('NodeAgentService._fetchDeviceToken: body=${response.body}');
        return null;
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map<String, dynamic>) return null;
      final token = body['device_token'];
      return token is String ? token : null;
    } catch (e, stack) {
      _debugLog('_fetchDeviceToken: exception: $e\n$stack');
      VLOG0('NodeMode: device token request failed: $e');
      return null;
    }
  }

  void _ensureUserInitialized() {
    try {
      // ignore: unused_local_variable
      final user = ApplicationInfo.user;
    } catch (_) {
      // Initialize dummy user for Node mode
      ApplicationInfo.user = User(uid: 0, nickname: 'node');
    }
  }

  Future<void> _applyLeaseCredentials(String leaseToken) async {
    final hash = HashUtil.hash(leaseToken);
    StreamingSettings.connectPasswordHash = hash;
    if (NodeAgentConfig.isHeadless) {
      VLOG0('NodeAgentService._applyLeaseCredentials: skipping SharedPreferences in headless mode');
    } else {
      await SharedPreferencesManager.setString('connectPasswordHash', hash);
    }
    ApplicationInfo.connectable = true;
    if (NodeAgentConfig.isHeadless) {
      VLOG0('NodeAgentService._applyLeaseCredentials: skipping SharedPreferences in headless mode');
    } else {
      await SharedPreferencesManager.setBool('allowConnect', true);
    }
  }

  Future<void> _clearLeaseState({required bool stopSessions}) async {
    if (stopSessions) {
      StreamedManager.stopAllSessions();
    }
    ApplicationInfo.connectable = false;
    StreamingSettings.connectPasswordHash = '';

    if (NodeAgentConfig.isHeadless) {
      VLOG0('NodeAgentService._clearLeaseState: skipping SharedPreferences in headless mode');
    } else {
      await SharedPreferencesManager.setBool('allowConnect', false);
      await SharedPreferencesManager.setString('connectPasswordHash', '');
    }
  }

  void _sendNodeHello() {
    if (NodeAgentConfig.deviceId.isEmpty) return;
    send('node_hello', {
      'device_id': NodeAgentConfig.deviceId,
      'region': NodeAgentConfig.region,
      'gpu_tier': NodeAgentConfig.gpuTier,
      'agent_version': NodeAgentConfig.agentVersion,
      'capabilities': {
        'city': NodeAgentConfig.city,
      },
    });
  }

  void _startNodeHeartbeat() {
    _nodeHeartbeatTimer?.cancel();
    final seconds = NodeAgentConfig.heartbeatSeconds <= 0
        ? 10
        : NodeAgentConfig.heartbeatSeconds;
    _nodeHeartbeatTimer = Timer.periodic(Duration(seconds: seconds), (_) {
      if (!isConnected) return;
      send('node_heartbeat', {
        'device_id': NodeAgentConfig.deviceId,
        'ts': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }

  void _stopNodeHeartbeat() {
    _nodeHeartbeatTimer?.cancel();
    _nodeHeartbeatTimer = null;
  }
}
