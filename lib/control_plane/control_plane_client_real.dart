import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../dev_settings.dart/develop_settings.dart';
import '../services/login_service.dart';
import '../services/secure_storage_manager.dart';
import '../services/shared_preferences_manager.dart';
import '../utils/websocket.dart'
    if (dart.library.js) '../utils/websocket_web.dart';
import 'control_plane_client.dart';
import 'control_plane_models.dart';

class ControlPlaneClientReal implements ControlPlaneClient {
  final LoginService _loginService;

  final _poolUpdatesController = StreamController<PoolUpdate>.broadcast();
  final _leaseUpdatesController = StreamController<LeaseUpdate>.broadcast();

  SimpleWebSocket? _socket;
  bool _connecting = false;

  ControlPlaneClientReal(this._loginService);

  @override
  Stream<PoolUpdate> get poolUpdates => _poolUpdatesController.stream;

  @override
  Stream<LeaseUpdate> get leaseUpdates => _leaseUpdatesController.stream;

  @override
  Future<void> connect() async {
    if (_socket != null || _connecting) return;
    _connecting = true;
    try {
      final accessToken = await _getValidAccessToken();
      if (accessToken == null || accessToken.isEmpty) {
        _connecting = false;
        return;
      }

      final url = _buildWsUrl(accessToken);
      _socket = SimpleWebSocket(url);

      _socket?.onMessage = (message) async {
        final map = _tryDecodeWsMessage(message);
        if (map == null) return;

        final type = map['type'];
        if (type is! String) return;
        final data = map['data'];

        switch (type) {
          case 'pool_update':
            {
              final payload =
                  data is Map<String, dynamic> ? data : <String, dynamic>{};
              final mode = payload['mode'] as String?;
              final rawNodes = payload['nodes'];
              final nodes = <PoolNode>[];
              if (rawNodes is List) {
                for (final item in rawNodes) {
                  if (item is Map<String, dynamic>) {
                    nodes.add(PoolNode.fromJson(item));
                  }
                }
              }
              _poolUpdatesController.add(PoolUpdate(
                isFull: mode == null ? true : mode.toLowerCase() == 'full',
                nodes: nodes,
              ));
              break;
            }
          case 'lease_update':
            {
              final payload =
                  data is Map<String, dynamic> ? data : <String, dynamic>{};
              final leaseJson = payload['lease'] is Map<String, dynamic>
                  ? payload['lease'] as Map<String, dynamic>
                  : payload;
              final lease = Lease.fromJson(leaseJson);
              _leaseUpdatesController.add(LeaseUpdate(lease));
              break;
            }
          default:
            break;
        }
      };

      _socket?.onClose = (_, __) async {
        _socket = null;
      };

      await _socket?.connect();
    } finally {
      _connecting = false;
    }
  }

  @override
  Future<void> disconnect() async {
    _socket?.close();
    _socket = null;
  }

  @override
  Future<List<PoolNode>> fetchPoolNodes({
    String? region,
    String? gpuTier,
    NodeStatus? status,
  }) async {
    final baseUrl = LoginService.baseUrl;
    final uri = Uri.parse('$baseUrl/api/pool/nodes/').replace(queryParameters: {
      if (region != null) 'region': region,
      if (gpuTier != null) 'gpu_tier': gpuTier,
      if (status != null) 'status': nodeStatusToWire(status),
    });

    final response = await http.get(uri, headers: await _getHeaders());
    final body = _decodeJson(response);
    if (response.statusCode != 200) {
      throw _asApiException(body, fallbackCode: 'HTTP_${response.statusCode}');
    }

    final nodes = (body['nodes'] as List<dynamic>? ?? const [])
        .map((e) => PoolNode.fromJson(e as Map<String, dynamic>))
        .toList();
    return nodes;
  }

  @override
  Future<RentResult> rent({
    required String region,
    required String gpuTier,
    required BillingUnit billingUnit,
    int count = 1,
    String? clientRequestId,
  }) async {
    final baseUrl = LoginService.baseUrl;
    final uri = Uri.parse('$baseUrl/api/lease/rent/');
    final payload = {
      'region': region,
      'gpu_tier': gpuTier,
      'billing_unit': billingUnitToWire(billingUnit),
      'count': count,
      if (clientRequestId != null) 'client_request_id': clientRequestId,
    };

    final response = await http.post(
      uri,
      headers: await _getHeaders(),
      body: jsonEncode(payload),
    );
    final body = _decodeJson(response);
    if (response.statusCode != 200) {
      throw _asApiException(body, fallbackCode: 'HTTP_${response.statusCode}');
    }

    final leases = (body['leases'] as List<dynamic>? ?? const [])
        .map((e) => Lease.fromJson(e as Map<String, dynamic>))
        .toList();

    final tokenMap = <String, String>{};
    final rawMap = body['lease_token_map'];
    if (rawMap is Map<String, dynamic>) {
      for (final entry in rawMap.entries) {
        tokenMap[entry.key] = entry.value as String;
      }
    }

    return RentResult(leases: leases, leaseTokenByLeaseId: tokenMap);
  }

  @override
  Future<List<Lease>> release({
    required List<String> leaseIds,
    String? clientRequestId,
  }) async {
    final baseUrl = LoginService.baseUrl;
    final uri = Uri.parse('$baseUrl/api/lease/release/');
    final payload = {
      'lease_ids': leaseIds,
      if (clientRequestId != null) 'client_request_id': clientRequestId,
    };

    final response = await http.post(
      uri,
      headers: await _getHeaders(),
      body: jsonEncode(payload),
    );
    final body = _decodeJson(response);
    if (response.statusCode != 200) {
      throw _asApiException(body, fallbackCode: 'HTTP_${response.statusCode}');
    }

    final leases = (body['leases'] as List<dynamic>? ?? const [])
        .map((e) => Lease.fromJson(e as Map<String, dynamic>))
        .toList();
    return leases;
  }

  @override
  Future<List<Lease>> fetchLeases() async {
    final baseUrl = LoginService.baseUrl;
    final uri = Uri.parse('$baseUrl/api/lease/list/');

    final response = await http.get(uri, headers: await _getHeaders());
    final body = _decodeJson(response);
    if (response.statusCode != 200) {
      throw _asApiException(body, fallbackCode: 'HTTP_${response.statusCode}');
    }

    final leases = (body['leases'] as List<dynamic>? ?? const [])
        .map((e) => Lease.fromJson(e as Map<String, dynamic>))
        .toList();
    return leases;
  }

  @override
  Future<BillingInfo> fetchBillingInfo() async {
    final baseUrl = LoginService.baseUrl;
    final uri = Uri.parse('$baseUrl/api/billing/info/');

    final response = await http.get(uri, headers: await _getHeaders());
    final body = _decodeJson(response);
    if (response.statusCode != 200) {
      throw _asApiException(body, fallbackCode: 'HTTP_${response.statusCode}');
    }

    return BillingInfo.fromJson(body);
  }

  @override
  Future<void> requestRemoteControlLease({
    required String leaseId,
    required Map<String, dynamic> settings,
  }) async {
    if (_socket == null) {
      throw const ControlPlaneApiException(
        code: 'WS_NOT_CONNECTED',
        message: 'WebSocket is not connected',
      );
    }
    final payload = {
      'type': 'requestRemoteControlLease',
      'data': {
        'lease_id': leaseId,
        'settings': settings,
      },
    };
    _socket!.send(jsonEncode(payload));
  }

  @override
  Future<void> deletePoolNode(String deviceId) async {
    final baseUrl = LoginService.baseUrl;
    final uri = Uri.parse('$baseUrl/api/admin/nodes/$deviceId/delete/');

    final response = await http.delete(uri, headers: await _getHeaders());
    if (response.statusCode != 200 && response.statusCode != 204) {
      final body = _decodeJson(response);
      throw _asApiException(body, fallbackCode: 'HTTP_${response.statusCode}');
    }
  }

  @override
  void dispose() {
    disconnect();
    _poolUpdatesController.close();
    _leaseUpdatesController.close();
  }

  Future<Map<String, String>> _getHeaders() async {
    String? accessToken;
    if (DevelopSettings.useSecureStorage) {
      accessToken = await SecureStorageManager.getString('access_token');
    } else {
      accessToken = SharedPreferencesManager.getString('access_token');
    }
    return {
      'Content-Type': 'application/json; charset=UTF-8',
      'Accept': 'application/json',
      if (accessToken != null && accessToken.isNotEmpty)
        'Authorization': 'Bearer $accessToken',
    };
  }

  Future<String?> _getValidAccessToken() async {
    String? accessToken;
    String? refreshToken;

    if (DevelopSettings.useSecureStorage) {
      accessToken = await SecureStorageManager.getString('access_token');
      refreshToken = await SecureStorageManager.getString('refresh_token');
    } else {
      accessToken = SharedPreferencesManager.getString('access_token');
      refreshToken = SharedPreferencesManager.getString('refresh_token');
    }

    if (accessToken == null || refreshToken == null) return null;
    if (LoginService.isTokenValid(accessToken)) return accessToken;

    final newAccess = await LoginService.doRefreshToken(refreshToken);
    if (newAccess != null && LoginService.isTokenValid(newAccess)) {
      if (DevelopSettings.useSecureStorage) {
        await SecureStorageManager.setString('access_token', newAccess);
      } else {
        await SharedPreferencesManager.setString('access_token', newAccess);
      }
      return newAccess;
    }
    return null;
  }

  String _buildWsUrl(String accessToken) {
    final base = Uri.parse(LoginService.baseUrl);
    final scheme = base.scheme.toLowerCase() == 'https' ? 'wss' : 'ws';
    final wsUri = base.replace(
      scheme: scheme,
      path: '/ws/',
      queryParameters: {'token': accessToken},
    );
    return wsUri.toString();
  }

  Map<String, dynamic>? _tryDecodeWsMessage(dynamic message) {
    try {
      if (message is Map<String, dynamic>) return message;
      if (message is String) {
        final decoded = jsonDecode(message);
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Map<String, dynamic> _decodeJson(http.Response response) {
    try {
      final text = utf8.decode(response.bodyBytes);
      if (text.trim().isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      return <String, dynamic>{'data': decoded};
    } catch (e) {
      // If decoding fails (e.g. HTML response), return the raw body as a message
      final rawBody = utf8.decode(response.bodyBytes);
      return <String, dynamic>{
        'code': 'RAW_RESPONSE',
        'message': 'Server returned non-JSON response (HTTP ${response.statusCode})',
        'details': rawBody.length > 200 ? rawBody.substring(0, 200) : rawBody,
      };
    }
  }

  ControlPlaneApiException _asApiException(
    Map<String, dynamic> body, {
    required String fallbackCode,
  }) {
    final code = (body['code'] as String?) ?? fallbackCode;
    final message = (body['message'] as String?) ?? 'Request failed';
    final details = body['details'];
    return ControlPlaneApiException(
        code: code, message: message, details: details);
  }
}
