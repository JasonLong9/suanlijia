// lib/config/custom_config.dart
class CustomConfig {
  // 是否启用 V11 定制模式 - 算力橙测试版禁用
  static const bool isV11 = false;
  // 品牌名称
  static const String appName = '云电脑';
  // 默认账号密码 (禁用自动登录)
  static const String defaultUsername = ''; 
  static const String defaultPassword = '';
  // 是否自动登录 - 禁用，手动登录测试
  static const bool autoLogin = false;
  // 是否默认隐藏窗口 - 禁用，确保 GUI 可见
  static const bool startHidden = false;
}
