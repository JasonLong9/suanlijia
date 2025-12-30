import 'package:get_it/get_it.dart';
import 'services/login_service.dart';
import 'services/websocket_service.dart';
import 'services/node_agent_service.dart';
import 'services/webrtc_service.dart';
import 'services/app_init_service.dart';
import 'services/streaming_manager.dart';
import 'services/streamed_manager.dart';
import 'services/admin_service.dart';
import 'services/marketplace_service.dart';
import 'control_plane/control_plane_client.dart';
import 'control_plane/control_plane_client_mock.dart';
import 'control_plane/control_plane_client_real.dart';
import 'control_plane/control_plane_config.dart';
import 'control_plane/control_plane_controller.dart';
import 'control_plane/lease_streaming_service.dart';

final getIt = GetIt.instance;

void setupServiceLocator() {
  // Services
  getIt.registerLazySingleton<LoginService>(() => LoginService());
  getIt.registerLazySingleton<WebSocketService>(
      () => WebSocketService());
  getIt.registerLazySingleton<NodeAgentService>(
      () => NodeAgentService(getIt<LoginService>()));
  getIt.registerLazySingleton<WebrtcService>(() => WebrtcService());
  getIt.registerLazySingleton<AppInitService>(
      () => AppInitService());
  getIt.registerLazySingleton<StreamingManager>(() => StreamingManager());
  getIt.registerLazySingleton<StreamedManager>(() => StreamedManager());
  getIt.registerLazySingleton<LeaseStreamingService>(
      () => LeaseStreamingService(getIt<StreamingManager>()));
  getIt.registerLazySingleton<AdminService>(
      () => AdminService(getIt<LoginService>()));
  getIt.registerLazySingleton<MarketplaceService>(
      () => MarketplaceService(getIt<LoginService>()));
  getIt.registerLazySingleton<ControlPlaneClient>(() {
    if (ControlPlaneConfig.useMock) {
      return ControlPlaneClientMock();
    }
    return ControlPlaneClientReal(getIt<LoginService>());
  });
  getIt.registerLazySingleton<ControlPlaneController>(
      () => ControlPlaneController(getIt<ControlPlaneClient>()));
}
