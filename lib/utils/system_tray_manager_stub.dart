class SystemTrayManager {
  static final SystemTrayManager _instance = SystemTrayManager._internal();
  factory SystemTrayManager() => _instance;
  SystemTrayManager._internal();

  Future<void> initialize({
    String iconPath = 'assets/images/cpp_logo',
    bool hideDockIconOnStart = false,
  }) async {
    // Do nothing on web
  }

  void showWindow() {}
  void hideWindow() {}
  void restart() {}
  void exitApp() {}
  Future<void> updateTooltip(String newTooltip) async {}
  Future<void> updateIcon(String newIconPath) async {}
}
