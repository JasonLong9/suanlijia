import 'package:slc/services/login_service.dart';

class MarketplaceService {
  // ignore: unused_field
  final LoginService _loginService;

  MarketplaceService(this._loginService);

  Future<List<dynamic>> fetchPublicDevices() async {
    // Mock implementation for now
    await Future.delayed(const Duration(seconds: 1));
    return [
      {
        'id': 'public_1',
        'device_name': 'Public GPU 3090',
        'device_type': 'Windows',
        'status': 'available',
        'price': '10.0',
        'specs': 'RTX 3090, 24GB VRAM'
      },
      {
        'id': 'public_2',
        'device_name': 'Public GPU 4090',
        'device_type': 'Linux',
        'status': 'available',
        'price': '15.0',
        'specs': 'RTX 4090, 24GB VRAM'
      },
    ];
  }

  Future<bool> rentDevice(String deviceId) async {
    // Mock implementation
    await Future.delayed(const Duration(seconds: 1));
    return true;
  }
}
