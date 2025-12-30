# 线B：Flutter 客户端 + Windows 节点守护程序开发计划（资源池 / 租赁 / 回收重启）

## 0. 目标与边界
**目标**：在复用现有 WebRTC/P2P 远控能力的前提下，新增“资源池租赁体验”和“Windows 节点守护程序能力”，实现：
- 用户：按地域/规格租用（支持多台）、进入远控、释放（立即停费）
- 节点：接收租赁指令、回 `lease_ready`（计费起点）、收到 release 后断会话并**强制重启系统**

**边界/约束**
- GPU 节点 Windows + 无盘：无需做镜像/实例交付，只需能重启并自动回到可用态
- 远控断开不停止计费；仅 release/offline 停费
- 月计费按自然月由后端处理；前端只展示账单/单位与金额

## 1. 可复用代码点（尽量不动串流主链路）
- WebSocket 连接与分发：`lib/services/websocket_service.dart`
- 控制端串流会话：`lib/services/streaming_manager.dart`、`lib/entities/session.dart`
- 被控端串流会话：`lib/services/streamed_manager.dart`
- Windows 服务态/系统权限能力：`lib/main.dart` + `plugins/hardware_simulator`

## 2. 线B 内部拆分（两人并行）
### 工程师B1（优先：前端页面）
- 资源池页（筛选/定价/租用 count）
- 我的租赁页（多台租赁列表：进入远控/释放）
- 账单页（余额/历史账单/当前租赁费用预估）
- 全程先接 `MockControlPlaneClient`，不依赖后端联调

### 工程师B2（基础设施：接口层/节点/重启/授权）
- [ ] `ControlPlaneClient` 抽象（Real + Mock）
- [x] 串流接入租赁授权（requestRemoteControlLease）
- [x] Node Agent 模式（设备身份连 WS、处理 lease_assigned/lease_release）
  - v10.2: 修复 Headless 模式卡死问题
  - v10.3: 修复私有部署环境下的 api_url 连接问题
- [ ] `rebootSystem()` 插件能力（Windows 原生）

## 3. 控制平面对接层（必须先做，支撑页面与节点）
### 3.1 建议目录结构
- `lib/control_plane/`
  - `control_plane_client.dart`（抽象接口）
  - `control_plane_client_real.dart`（HTTP + WS）
  - `control_plane_client_mock.dart`（本地状态机模拟）
  - `models/`（Node/Lease/PricePlan/Billing 等 DTO）
  - `state/`（Pool/Lease 状态管理：Bloc/Notifier 均可，但集中管理）

### 3.2 Mock 策略（让 UI 不等后端）
- `rent`：返回 leases（ASSIGNED）并在 N 秒后自动推进 READY/ACTIVE（模拟 `lease_ready`）
- `release`：立即把 lease 推进 ENDED（并记录 end_reason=USER_RELEASE）
- `pool_update`：模拟节点 FREE/IN_USE 变化（方便 UI 验证）

## 4. 用户端 UI 任务清单（B1）
### 4.1 资源池页（Pool）
- 筛选：`region`、`gpu_tier(7档)`、`billing_unit(minute/hour/day/week/month)`
- 展示：价格、库存（FREE 数）、节点状态分布（可简化）
- 操作：选择 `count`（多台）-> 租用 -> 跳转“我的租赁”

### 4.2 我的租赁页（Leases）
- 列表：每个 lease 展示 `region/gpu_tier/billing_unit`、开始时间、已用时长、预估费用、状态
- 操作：
  - “进入远控”：READY/ACTIVE 时可用
  - “释放资源停止计费”：立即调用 release，并显示“已结束/释放中”
- 异常：节点掉线导致 lease_end_reason=NODE_OFFLINE（需明显提示）

### 4.3 账单页（Billing）
- 当前余额（如有）
- 当前租赁汇总（可选）
- 历史账单列表（可筛选时间/状态）

### 4.4 导航集成建议
现有 `MainScreen` 底部导航只有设备页/设置页（`lib/pages/main_page.dart`）。
- 建议新增 Tab：`资源池`、`我的租赁`（设置页保留）
- 保留原 `DevicesPage` 用于“传统 P2P 自有设备互控”，避免和资源池逻辑混在一起

## 5. 串流与租赁授权接入（B2）
### 5.1 目标
复用现有 WebRTC 串流，但把“是否允许发起远控”改成“租赁授权”：
- 控制端发起远控时必须携带 `lease_id/lease_token`
- 服务端校验 lease 归属与有效性后，才转发信令到目标节点

### 5.2 客户端改造点
- [x] 进入远控时自动注入 `lease_token`（不让用户手输连接密码）
- [x] 新增/替换 WS 事件：`requestRemoteControlLease`（与现有 `requestRemoteControl` 区分）
- 尽量不改 `StreamingManager.startStreaming(...)` 主流程，仅在“发起 request”处切换事件与数据

## 6. Node Agent（Windows 节点守护程序）任务清单（B2）
### 6.1 Node Mode（设备身份）
- 节点启动后使用 `device_token` 连接 WS（与用户登录隔离）
- 上报 `node_hello`、定时 `node_heartbeat`

### 6.2 租赁指令处理
- 收到 `lease_assigned`：
  - 清理残留：断开现有会话、恢复显示器配置（复用 `StreamedManager.stopStreaming` 等逻辑）
  - 设置本次 `lease_token` 为连接密钥（密码 hash）
  - 上报 `lease_ready`（计费起点）
- 收到 `lease_release`：
  - 断开所有会话（遍历 `StreamedManager.sessions` 调用 `stopStreaming`）
  - 调用 `rebootSystem()` 强制系统重启

## 7. Windows 强制重启能力（B2）
在 `plugins/hardware_simulator` 增加 `rebootSystem()`：
- Windows 原生实现建议：`shutdown.exe /r /t 0 /f`（服务态更稳定）
- 节点必须在系统权限/服务态运行，确保重启命令可执行

## 8. 自测与验收（线B）
### 8.1 Mock 自测（不依赖后端）
- UI 全流程：筛选 -> rent(count) -> READY/ACTIVE -> 进入远控按钮可用 -> release -> 结束展示

### 8.2 真联调（依赖线A）
- E2E：rent → node ready（开始计费）→ 远控 → 断开不停费 → release 立刻停费 → node reboot → 节点回 FREE
- 异常：租赁中节点掉线 -> lease 立即结束并提示原因

## 9. 里程碑（建议）
- M0：ControlPlaneClient(Mock/Real 骨架) + UI 用 Mock 跑通
- M1：Node Agent 处理 assigned/ready/release + rebootSystem()
- M2：串流授权接入（requestRemoteControlLease）+ 与线A 联调
- M3：完善账单展示、异常提示、体验打磨

