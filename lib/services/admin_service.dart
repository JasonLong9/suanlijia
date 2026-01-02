import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:slc/services/login_service.dart';
import 'package:slc/services/secure_storage_manager.dart';
import 'package:slc/services/shared_preferences_manager.dart';
import 'package:slc/dev_settings.dart/develop_settings.dart';
import '../control_plane/control_plane_models.dart';

class AdminService {
  final LoginService _loginService;

  AdminService(this._loginService);

  Future<Map<String, String>> _getHeaders() async {
    String? accessToken;
    if (DevelopSettings.useSecureStorage) {
      accessToken = await SecureStorageManager.getString('access_token');
    } else {
      accessToken = SharedPreferencesManager.getString('access_token');
    }
    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('Missing access token');
    }
    return {
      'Content-Type': 'application/json; charset=UTF-8',
      'Authorization': 'Bearer $accessToken',
    };
  }

  Future<List<PoolNode>> fetchNodes() async {
    final baseUrl = LoginService.baseUrl;
    final url = Uri.parse('$baseUrl/api/admin/nodes/');
    final response = await http.get(url, headers: await _getHeaders());

    if (response.statusCode != 200) {
      throw Exception('Failed to load nodes: ${response.statusCode}');
    }

    final decoded = json.decode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid response');
    }
    final rawNodes = decoded['nodes'];
    if (rawNodes is! List) return const [];
    return rawNodes
        .whereType<Map<String, dynamic>>()
        .map(PoolNode.fromJson)
        .toList();
  }

  Future<void> rebootNode(String deviceId, {bool bmc = false}) async {
    final baseUrl = LoginService.baseUrl;
    final url = Uri.parse('$baseUrl/api/admin/nodes/$deviceId/reboot/');
    final response = await http.post(
      url,
      headers: await _getHeaders(),
      body: jsonEncode({
        if (bmc) 'type': 'bmc',
      }),
    );
    if (response.statusCode != 200 && response.statusCode != 202) {
      throw Exception('Reboot failed: ${response.statusCode}');
    }
  }

  Future<void> forceReleaseNode(String deviceId) async {
    final baseUrl = LoginService.baseUrl;
    final url = Uri.parse('$baseUrl/api/admin/nodes/$deviceId/force_release/');
    final response = await http.post(
      url,
      headers: await _getHeaders(),
      body: jsonEncode({}),
    );
    if (response.statusCode != 200) {
      throw Exception('Force release failed: ${response.statusCode}');
    }
  }

  Future<PoolNode> updateNode({
    required String deviceId,
    String? nickname,
    String? region,
    String? gpuTier,
    String? bmcAddress,
    String? bmcUsername,
    String? bmcPassword,
  }) async {
    final baseUrl = LoginService.baseUrl;
    final url = Uri.parse('$baseUrl/api/admin/nodes/$deviceId/');
    
    // 构建 capabilities map
    final capabilities = <String, dynamic>{};
    if (bmcAddress != null) capabilities['bmc_address'] = bmcAddress;
    if (bmcUsername != null) capabilities['bmc_username'] = bmcUsername;
    if (bmcPassword != null) capabilities['bmc_password'] = bmcPassword;

    final payload = <String, dynamic>{
      if (nickname != null) 'nickname': nickname,
      if (region != null) 'region': region,
      if (gpuTier != null) 'gpu_tier': gpuTier,
      if (capabilities.isNotEmpty) 'capabilities': capabilities,
    };

    final response = await http.patch(
      url,
      headers: await _getHeaders(),
      body: jsonEncode(payload),
    );
    if (response.statusCode != 200) {
      throw Exception('Update failed: ${response.statusCode}');
    }
    final decoded = json.decode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid response');
    }
    return PoolNode.fromJson(decoded);
  }
}
