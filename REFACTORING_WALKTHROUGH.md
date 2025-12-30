# 结构重构演练 (Walkthrough)

## 变更摘要
我们成功地将 `CloudPlayPlus` 项目从静态服务架构迁移到了基于 **依赖注入 (DI)** 和 **BLoC** 的现代架构。

### 核心变更
1.  **依赖注入 (DI)**
    -   引入了 `get_it` 库。
    -   创建了 [lib/service_locator.dart](file:///SuanLiJia/lib/service_locator.dart) 来注册和管理服务实例。
    -   [LoginService](file:///SuanLiJia/lib/services/login_service.dart#22-541)、[WebSocketService](file:///SuanLiJia/lib/services/websocket_service.dart#32-336)、[WebrtcService](file:///SuanLiJia/lib/services/webrtc_service.dart#7-113) 和 [AppInitService](file:///SuanLiJia/lib/services/app_init_service.dart#26-112) 现在都是单例实例，不再包含静态方法。

2.  **状态管理 (BLoC)**
    -   引入了 `flutter_bloc` 和 `equatable`。
    -   创建了 [AuthBloc](file:///SuanLiJia/lib/blocs/auth/auth_bloc.dart#9-61) (`lib/blocs/auth/`) 来管理登录状态。
    -   创建了 `ConnectionBloc` (`lib/blocs/connection/`) 来管理 WebSocket 连接和设备列表。

3.  **服务重构**
    -   **LoginService**: 移除了所有 `static` 关键字。现在通过 `getIt<LoginService>()` 访问。
    -   **WebSocketService**: 移除了所有 `static` 关键字。现在通过构造函数注入 `LoginService`。
    -   **AppInitService**: 移除了所有 `static` 关键字。现在通过构造函数注入 `LoginService` 和 `WebSocketService`。

4.  **入口点更新**
    -   `main.dart` 现在调用 `setupServiceLocator()` 初始化服务。
    -   `MyApp` 被包裹在 `MultiBlocProvider` 中，提供全局的 `AuthBloc` 和 `ConnectionBloc`。
    -   `InitPage` 更新为使用 `getIt` 获取服务实例。
    -   **UI 和实体修复**:
        -   `DeviceTilePage` (`lib/utils/widgets/device_tile_page.dart`): 修复了静态调用。
        -   `Session` (`lib/entities/session.dart`): 修复了静态调用。
        -   `ReconnectScreen` (`lib/pages/reconnect_page.dart`): 修复了静态调用。
        -   `User` (`lib/entities/user.dart`): 添加了 `chattoken` 字段。
    -   **TODO 修复**:
        -   `LoginService`: 实现了用户信息的更新。
        -   `WebSocketService`: 添加了 Token 过期时的错误提示。
        -   `AuthBloc`: 实现了获取用户昵称的逻辑。

## 验证步骤

### 1. 静态分析
运行以下命令以确保没有编译错误：
```bash
flutter analyze lib/main.dart lib/services/login_service.dart lib/services/websocket_service.dart lib/services/app_init_service.dart lib/pages/init_page.dart
```

### 2. 运行应用
由于这是一个结构性重构，建议在 Web 或桌面环境中运行应用进行全面回归测试：
```bash
flutter run -d chrome --web-browser-flag "--disable-web-security"
```

### 3. 关键测试点
-   **启动流程**: 应用应能正常启动并进入 `InitPage`。
-   **登录**: 尝试登录，验证 `AuthBloc` 是否正确处理状态。
-   **连接**: 登录后，验证 WebSocket 是否连接成功，设备列表是否加载。
-   **重连**: 模拟网络断开，验证重连逻辑（由 `WebSocketService` 和 `ConnectionBloc` 处理）。

## 下一步建议
-   **迁移更多页面**: 将 `LoginPage`、`MainPage` 等页面迁移为使用 `BlocBuilder` 或 `BlocListener` 来响应状态变化，而不是直接调用服务或依赖回调。
-   **单元测试**: 为 `AuthBloc` 和 `ConnectionBloc` 编写单元测试，利用 Mock 服务来模拟各种场景。
