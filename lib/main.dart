import 'dart:async';
import 'dart:io' if (dart.library.js) 'utils/web_util.dart';

import 'package:slc/controller/hardware_input_controller.dart';
import 'package:slc/dev_settings.dart/develop_settings.dart';
import 'package:slc/services/app_init_service.dart';
import 'package:slc/services/webrtc/webrtc_initializer_platform.dart';
import 'package:slc/utils/system_tray_manager.dart';
import 'package:flutter/material.dart';
import 'package:hardware_simulator/hardware_simulator.dart';
import 'package:provider/provider.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'base/logging.dart';
import 'controller/screen_controller.dart';
import 'global_settings/streaming_settings.dart';
import 'pages/init_page.dart';
import 'services/app_info_service.dart';
import 'services/login_service.dart';
import 'services/secure_storage_manager.dart';
import 'services/shared_preferences_manager.dart';
import 'theme/theme_provider.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'utils/widgets/virtual_gamepad/control_manager.dart';
import 'service_locator.dart';
import 'blocs/auth/auth_bloc.dart';
import 'blocs/connection/connection_bloc.dart';
import 'services/websocket_service.dart';
import 'control_plane/control_plane_controller.dart';
import 'control_plane/node_agent_config.dart';
import 'blocs/streaming/streaming_bloc.dart';
import 'services/streaming_manager.dart';
import 'control_plane/headless_node_agent.dart';
import 'pages/node_mode_page.dart';
import 'config/custom_config.dart';
import 'services/node_agent_service.dart';

void main(List<String> args) async {
  // 最早期日志
  _writeStartupLog('main() started, args: $args');

  setupServiceLocator();
  LoginService.init();

  // Check if running in headless mode (service mode on Windows)
  final isHeadless = args.contains('--headless') ||
      args.contains('-headless') ||
      args.contains('/headless');

  _writeStartupLog('isHeadless: $isHeadless');
  _writeStartupLog('NodeAgentConfig.enabled: ${NodeAgentConfig.enabled}');
  _writeStartupLog('NodeAgentConfig.deviceId: ${NodeAgentConfig.deviceId}');
  _writeStartupLog('NodeAgentConfig.apiUrl: ${NodeAgentConfig.apiUrl}');

  if (isHeadless) {
    // === HEADLESS MODE: 后台服务（仍需初始化 Binding 以使用插件/平台通道） ===
    NodeAgentConfig.isHeadless = true;
    DevelopSettings.isDebugging = true;
    _writeStartupLog('HEADLESS mode starting...');
    _writeStartupLog('Config - deviceId: ${NodeAgentConfig.deviceId}');
    _writeStartupLog('Config - apiUrl: ${NodeAgentConfig.apiUrl}');

    // Headless 模式也需要初始化 Binding，否则无法使用 flutter_webrtc / hardware_simulator 等插件。
    WidgetsFlutterBinding.ensureInitialized();

    try {
      // 直接启动纯 Dart 的 headless agent
      final agent = HeadlessNodeAgent();
      await agent.start();
      _writeStartupLog('HeadlessNodeAgent started');
      await agent.runForever();
    } catch (e, stack) {
      _writeStartupLog('ERROR: $e\n$stack');
    }

    _writeStartupLog('HEADLESS mode terminated');
    return;
  }

  // === GUI MODE: Normal Flutter application ===
  VLOG0('[Main] Starting in GUI mode...');
  _writeStartupLog('Starting in GUI mode...');
  
  WidgetsFlutterBinding.ensureInitialized();
  await AppPlatform.init();
  await ScreenController.initialize();
  await SharedPreferencesManager.init();
  // flutter_secure_storage(Web) 依赖 WebCrypto（需要 HTTPS / localhost 的安全上下文）。
  // 当前我们的 Web 部署是 http://<ip>:8080，因此 Web 端不要初始化 secure storage，避免运行时崩溃。
  if (DevelopSettings.useSecureStorage && !AppPlatform.isWeb) {
    SecureStorageManager.init();
  }
  //AppInitService depends on SharedPreferencesManager
  await AppInitService.init();

  if (AppPlatform.isWindows && !ApplicationInfo.isSystem) {
    bool startAsSys = await HardwareSimulator.registerService();
    if (startAsSys == true) {
      exit(0);
    }
  }

  // 使用新的 WebRTC 初始化器
  await createWebRTCInitializer().initialize();

  if (NodeAgentConfig.enabled) {
    await getIt<NodeAgentService>().init();
  }

  StreamingSettings.init();
  InputController.init();
  await ControlManager().loadControls();
  if (AppPlatform.isWeb) {
    setUrlStrategy(null);
  }
  runApp(const MyApp());
  if (AppPlatform.isWindows || AppPlatform.isMacos || AppPlatform.isLinux) {
    doWhenWindowReady(() {
      const initialSize = Size(400, 450);
      appWindow.minSize = initialSize;
      appWindow.alignment = Alignment.center;
      // 算力橙测试版：禁用窗口隐藏，确保 GUI 可见
      // 原逻辑：NodeAgentConfig.enabled 时隐藏窗口，现已禁用

      if (CustomConfig.isV11 && CustomConfig.startHidden) {
        appWindow.hide();
        // 注意：这里不要 return，继续执行后面的 SystemTray 初始化，否则托盘图标出不来
      }

      if (AppPlatform.isDeskTop) {
        SystemTrayManager().initialize();
      }
      if (ApplicationInfo.connectable && AppPlatform.isWindows) {
        AppInitService.appInitState.then((state) async {
          if (state == AppInitState.loggedin) {
            appWindow.hide();
          } else {
            appWindow.show();
          }
        }).catchError((error) {
          VLOG0('Error: failed appInitState 2');
        });
      } else {
        appWindow.show();
      }
    });
  }
}

void _writeStartupLog(String msg) {
  try {
    final logDir = Directory(r'C:\ProgramData\SLC\logs');
    if (!logDir.existsSync()) logDir.createSync(recursive: true);
    final logFile = File('${logDir.path}\\startup.log');
    logFile.writeAsStringSync(
      '[${DateTime.now().toIso8601String()}] $msg\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {}
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          create: (context) => AuthBloc(getIt<LoginService>()),
        ),
        BlocProvider<ConnectionBloc>(
          create: (context) => ConnectionBloc(getIt<WebSocketService>()),
        ),
        BlocProvider<StreamingBloc>(
          create: (context) => StreamingBloc(getIt<StreamingManager>()),
        ),
      ],
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (context) => ThemeProvider()),
          ChangeNotifierProvider.value(value: getIt<ControlPlaneController>()),
        ],
        child: Consumer<ThemeProvider>(
          builder: (context, themeProvider, child) {
            return MaterialApp(
              title: CustomConfig.isV11 ? CustomConfig.appName : 'SLC',
              theme: themeProvider.lightTheme,
              darkTheme: themeProvider.darkTheme,
              themeMode: themeProvider.themeMode,
              // 算力橙测试版：强制使用标准登录页面
              home: NodeAgentConfig.enabled ? const NodeModePage() : const InitPage(),
              debugShowCheckedModeBanner: false,
            );
          },
        ),
      ),
    );
  }
}
