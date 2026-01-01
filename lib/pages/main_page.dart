import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:slc/controller/screen_controller.dart';
import 'package:slc/pages/control_plane/billing_page.dart';
import 'package:slc/pages/control_plane/leases_page.dart';
import 'package:slc/pages/admin/cluster_dashboard_page.dart';
import 'package:slc/services/app_info_service.dart';
import 'package:slc/services/streamed_manager.dart';
import 'package:slc/services/websocket_service.dart';
import 'package:slc/theme/fixed_colors.dart';
import 'package:slc/utils/system_tray_manager.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../settings_screen.dart';
import '../service_locator.dart';
import '../control_plane/control_plane_controller.dart';
import 'control_plane/pool_page.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  
  // TODO: 从 AuthBloc 获取实际管理员状态
  // 目前硬编码为 true 以便测试
  bool get _isAdmin => true;

  @override
  initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WebSocketService.init();
    getIt<ControlPlaneController>().start();

    if (AppPlatform.isAndroidTV) {
      _children = const [
        PoolPage(),
      ];
      _navItems = const [
        BottomNavigationBarItem(
          icon: Icon(Icons.computer),
          label: '云电脑',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings),
          label: '设置',
        ),
      ];
      return;
    }

    // 根据是否为管理员显示不同的导航
    if (_isAdmin) {
      _children = [
        const ClusterDashboardPage(),  // 管理员: 集群管理
        const PoolPage(),
        const LeasesPage(),
        const BillingPage(),
        const SettingsScreen(),
      ];
      _navItems = const [
        BottomNavigationBarItem(
          icon: Icon(Icons.dns),
          label: '集群',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.cloud),
          label: '资源池',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.assignment),
          label: '我的租赁',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.receipt_long),
          label: '账单',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings),
          label: '设置',
        ),
      ];
    } else {
      // 普通用户: 没有集群管理，从资源池开始
      _children = [
        const PoolPage(),
        const LeasesPage(),
        const BillingPage(),
        const SettingsScreen(),
      ];
      _navItems = const [
        BottomNavigationBarItem(
          icon: Icon(Icons.cloud),
          label: '资源池',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.assignment),
          label: '我的租赁',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.receipt_long),
          label: '账单',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings),
          label: '设置',
        ),
      ];
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && AppPlatform.isMobile) {
      WebSocketService.reconnect();
    }
  }

  void onTabTapped(int index) {
    if (AppPlatform.isAndroidTV && index == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => const SettingsScreen()),
      );
      return;
    }
    setState(() {
      _currentIndex = index;
    });
  }

  late final List<Widget> _children;
  late final List<BottomNavigationBarItem> _navItems;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
        valueListenable: StreamedManager.currentlyStreamedCount,
        builder: (context, streamedcount, child) {
          if (streamedcount != 0 && AppPlatform.isWindows) {
            windowManager.setAsFrameless();
            return Scaffold(
                backgroundColor: Colors.white,
                body: Column(
                  children: [
                    AnimatedTextKit(
                      animatedTexts: [
                        ColorizeAnimatedText(
                          'Cloud Play Plus',
                          textStyle: colorizeTextStyle,
                          colors: colorizeColors,
                        ),
                      ],
                      isRepeatingAnimation: false,
                      onTap: () {
                        //print("Tap Event");
                      },
                    ),
                    const SizedBox(width: 20.0, height: 30.0),
                    const Text('正在被以下客户端远程连接。', style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 12),
                    Table(
                      border: TableBorder.all(),
                      columnWidths: const {
                        0: FlexColumnWidth(2),
                        1: FlexColumnWidth(3),
                      },
                      children: [
                        // 表头
                        const TableRow(
                          //decoration: BoxDecoration(color: Colors.grey),
                          children: [
                            TableCell(
                              child: Padding(
                                padding: EdgeInsets.all(8),
                                child: Text('实例名',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center),
                              ),
                            ),
                            TableCell(
                              child: Padding(
                                padding: EdgeInsets.all(8),
                                child: Text('用户昵称',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center),
                              ),
                            ),
                            TableCell(
                              child: Padding(
                                padding: EdgeInsets.all(8),
                                child: Text('操作',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center),
                              ),
                            ),
                          ],
                        ),
                        // 表格数据
                        ...StreamedManager.sessions.values
                            .map((session) => TableRow(
                                  children: [
                                    TableCell(
                                      child: Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Text(
                                            session.controller.devicename,
                                            textAlign: TextAlign.center),
                                      ),
                                    ),
                                    TableCell(
                                      child: Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Text(session.controller.nickname,
                                            textAlign: TextAlign.center),
                                      ),
                                    ),
                                    TableCell(
                                      child: Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: ElevatedButton(
                                          onPressed: () {
                                            StreamedManager.stopStreaming(
                                                session.controller);
                                          },
                                          child: const Text('断开连接',
                                              style: TextStyle(fontSize: 12)),
                                          style: ElevatedButton.styleFrom(
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                )),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () {
                        SystemTrayManager().hideWindow();
                      },
                      child: const Text('最小化到系统托盘',
                          style: TextStyle(fontSize: 18)),
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ));
          }
          if (AppPlatform.isWindows) {
            windowManager.setTitleBarStyle(TitleBarStyle.normal);
          }
          return Stack(
            children: [
              Scaffold(
                backgroundColor: Colors.transparent,
                body: Stack(
                  children: [
                    IndexedStack(
                      index: _currentIndex,
                      children: _children,
                    ),
                  ],
                ),
                // 使用 ValueListenableBuilder 监听 showBottomNav 的状态
                bottomNavigationBar: ValueListenableBuilder<bool>(
                  valueListenable: ScreenController.showBottomNav,
                  builder: (context, showNavBar, child) {
                    if (!showNavBar) return const SizedBox();
                    return BottomNavigationBar(
                      type: BottomNavigationBarType.fixed,
                      onTap: onTabTapped,
                      currentIndex: _currentIndex,
                      items: _navItems,
                    );
                  },
                ),
              ),
            ],
          );
        });
  }
}

class GamesPage extends StatelessWidget {
  const GamesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(), //Text('GamesPage Page'),
    );
  }
}
