# 云电脑管理平台二次开发计划（CloudPlayPlus）

## 1. 背景与目标
现有 CloudPlayPlus 更偏向“用户与设备一对一/点对点（P2P）远控”。本次二次开发目标是在尽量复用现有 WebRTC 串流与信令链路的前提下，新增“控制平面（Control Plane）”，将分散的 GPU 服务器纳入统一调度、租赁与计费，形成可运营的**云电脑/算力资源管理平台**。

**核心目标**
- 支持多地域、多规格 GPU 节点纳管与调度（集群资源池）。
- 超级管理员可全局查看节点状态、强制释放、禁用/维护、重启。
- 用户支持同时租用多台机器；用户释放时**立即停止计费**并触发远端 GPU 节点**强制重启 Windows 系统**。
- 计费体系支持按分钟/小时/天/周/月等多种计费方式，并区分地域与 GPU 规格定价。

## 2. 约束与假设
- GPU 服务器运行 **Windows**，并使用**无盘系统**：无需做镜像/实例安装，只需保证“开机即自动进入可用状态”。
- **计费开始点**：节点守护程序确认“租赁就绪”（`lease_ready`）后开始计时。
- **计费停止点**：
  - 用户点击“释放资源停止计费”后立即停止计费（与节点实际重启完成无关）。
  - 节点掉线（WebSocket 断开/心跳超时）立即停止计费（异常结束）。
- 用户主动断开远控但不释放：**不停止计费**。
- 计费取整规则：**不足 1 个计费单位按 1 个计费单位计算**（分钟/小时/天/周/月均遵循）。

## 3. 角色与权限
- **User（客户）**：浏览资源池、租用/释放、查看账单、同时管理多台租赁机器。
- **Super Admin（超级管理员）**：全量节点/租赁/账单视图；禁用节点、维护模式、强制释放、强制重启、查看审计日志。
- **Node Agent（节点守护程序）**：运行在 GPU 服务器上（Windows），使用“设备身份”与平台建立连接，接收租赁/释放指令，执行回收并强制系统重启。

## 4. 架构拆分：控制平面 vs 串流平面
### 4.1 串流平面（尽量复用现有能力）
复用现有 WebRTC/P2P 远控能力（信令通过服务端 WebSocket 转发）。
- WebSocket 连接与消息分发：`lib/services/websocket_service.dart`
- 控制端会话：`lib/services/streaming_manager.dart`、`lib/entities/session.dart`
- 被控端会话：`lib/services/streamed_manager.dart`

### 4.2 控制平面（新增）
新增租赁、授权、调度、计费、管理台等能力；原则是**控制平面做决策**，串流平面只负责传输。

## 5. 核心数据模型（建议后端为准，客户端做映射）
> 关键：区分稳定 `device_id` 与在线 `connection_id`。现有 `Device.uid` 实际是 `owner_id`（`lib/entities/device.dart`），不适用于资源池。

### 5.1 Node（节点）
- `device_id`：稳定唯一标识（UUID 或自增 ID）
- `connection_id`：节点当前 WebSocket 连接会话 ID（可变）
- `region`：地域（如 `cn-shanghai`）
- `gpu_tier`：GPU 规格（如 `rtx-4090-24g`，或内部 7 档枚举）
- `status`：`OFFLINE | FREE | ASSIGNED | IN_USE | RELEASING | DISABLED | MAINTENANCE`
- `last_seen`：最后心跳时间
- `agent_version`：守护程序版本
- `capabilities`：可选（分辨率上限/编码能力等）

### 5.2 Lease（租赁）
- `lease_id`
- `user_id`
- `device_id`
- `status`：`PENDING | ASSIGNED | READY | ACTIVE | RELEASING | ENDED`
- `assigned_at / started_at / ended_at`
- `end_reason`：`USER_RELEASE | NODE_OFFLINE | ADMIN_FORCE_RELEASE | TIMEOUT | ERROR`
- `billing_unit`：`minute | hour | day | week | month`
- `unit_price`：按“地域+规格+计费单位”查得
- `billed_units`：按取整规则计算
- `amount`：本次费用
- `lease_token`：高熵一次性连接密钥（用于远控授权/自动填充连接密码）

### 5.3 Pricing（定价）
- `PricePlan`：`region + gpu_tier + billing_unit -> unit_price`
- 允许配置不同币种/税率（可选），建议先固定币种。

## 6. 状态机与关键规则
### 6.1 节点状态（NodeStatus）
- `OFFLINE`：无心跳/断连
- `FREE`：在线且可分配
- `ASSIGNED`：已分配给某租赁，等待就绪
- `IN_USE`：租赁已 ready 并激活（计费进行中）
- `RELEASING`：释放中（将触发重启）
- `DISABLED/MAINTENANCE`：不可分配

### 6.2 租赁状态（LeaseStatus）
`PENDING -> ASSIGNED -> READY(start计费) -> ACTIVE -> RELEASING(stop计费) -> ENDED`

### 6.3 计费算法（统一抽象）
- minute/hour/day/week：
  - `unit_seconds`：minute=60、hour=3600、day=86400、week=604800
  - `duration = ended_at - started_at`
  - `billed_units = max(1, ceil(duration / unit_seconds))`
- month（自然月）：按下方“自然月计费口径”单独计算
- stop 触发：
  - 用户 release：`ended_at = now`（先结算再重启）
  - 节点 offline：`ended_at = offline_detected_at`

#### 自然月计费口径（实现要求）
为避免“刚跨月就被算 2 个月”或“整月被算 2 个月”的边界问题，建议统一采用半开区间：
- 计费时间段：`[started_at, ended_at)`（`ended_at` 不计入）
- `billed_months = months_between(YearMonth(started_at), YearMonth(ended_at - ε)) + 1`
  - 若 `ended_at` 恰好是某月 1 日 00:00:00，则 `ended_at - ε` 落在上一个月，整月只计 1 个月
  - 若跨入下一个自然月任意时刻，则计入新月（不足 1 月按 1 月）
- `YearMonth()` 的时区必须固定（建议使用业务账务时区，如 `Asia/Shanghai`，并全链路统一）

## 7. 控制平面接口与协议（后端实现为主）
### 7.1 REST API（示例）
- `GET /api/pool/nodes?region=&gpu_tier=`：资源池列表（含状态与价格）
- `POST /api/lease/rent`：创建租赁（请求：region/gpu_tier/billing_unit/数量等）
- `POST /api/lease/release`：释放租赁（幂等）
- `GET /api/billing/info`：余额、当前租赁、历史账单

Admin：
- `GET /api/admin/nodes`
- `POST /api/admin/nodes/{device_id}/disable|enable|maintenance`
- `POST /api/admin/leases/{lease_id}/force_release`
- `POST /api/admin/nodes/{device_id}/reboot`

### 7.2 WebSocket 消息（建议）
设备侧（Node Agent）：
- `node_hello`：上线注册（device_id/region/gpu_tier/version）
- `node_heartbeat`：心跳（last_seen）
- `lease_assigned`：下发租赁（lease_id、lease_token、billing_unit、用户信息可选）
- `lease_ready`：节点就绪（**计费起点**）
- `lease_release`：释放指令（触发断会话+系统重启）

用户侧（Client）：
- `pool_update`：资源池变更推送
- `lease_update`：租赁状态推送

## 8. Node Agent（Windows GPU 服务器守护程序）改造计划
### 8.1 运行形态
优先复用现有 Windows “系统权限/服务态”能力：
- 入口：`lib/main.dart` 已存在 `HardwareSimulator.registerService()` 逻辑
- 目标：节点开机自动运行，后台常驻，确保具备“强制系统重启”权限

### 8.2 强制重启能力
新增平台能力 `rebootSystem()`（建议放在 `plugins/hardware_simulator`）：
- Windows 实现建议：`shutdown.exe /r /t 0 /f` 或系统 API（服务态更稳定）
- Node Agent 收到 `lease_release`：
  1) 断开所有会话：遍历 `StreamedManager.sessions` 并调用 `StreamedManager.stopStreaming(...)`（`lib/services/streamed_manager.dart`）
  2) 上报 `lease_releasing`（可选）
  3) 立即调用 `rebootSystem()`

### 8.3 “租赁就绪”与远控密码复用
复用现有“连接密码校验”机制（Host 端对密码 hash 校验）：
- 后端生成 `lease_token` 下发到节点
- 节点将 `lease_token` 写入本次连接密码（hash 存储）
- 节点完成清理与准备后发送 `lease_ready`
- 客户端连接时自动填充 `lease_token`，用户无需输入密码

## 9. Flutter 客户端（用户端）改造计划
### 9.1 新增/调整页面
- 资源池页：按地域/规格筛选，支持一次租用多台（数量选择）
- 我的租赁页：展示多台租赁的状态（READY/ACTIVE/RELEASING），进入远控、释放
- 账单页：展示当前费用预估、历史账单与明细
-（可选）租赁详情：连接信息、时长、价格、结束原因

### 9.2 复用与最小侵入
- 远控仍复用 `StreamingManager.startStreaming(...)`（`lib/services/streaming_manager.dart`）
- 但远控请求需携带 `lease_id/lease_token`，由后端校验授权后才转发给节点
- `DevicesPage` 可保留给“自有设备/传统 P2P”，云电脑资源池建议独立入口，避免现有按 `uid(owner_id)` 分组逻辑干扰

## 10. 超级管理员控制台（Admin Dashboard）
功能清单（优先级从高到低）：
- 节点总览：地域/规格维度统计，状态分布（FREE/IN_USE/OFFLINE…）
- 节点列表：搜索、筛选、查看占用租赁与用户、最后心跳、版本
- 操作：禁用/维护、强制释放（先停费/结算策略由后端决定）、强制重启
- 账单/租赁审计：按用户/节点/时间检索，导出（可选）

## 11. 调度与价格体系（多地域 + 7 档 GPU + 多计费单位）
### 11.1 调度策略（MVP）
输入：`region`、`gpu_tier`、`count`、`billing_unit`
- 只分配 `FREE` 且非 `MAINTENANCE/DISABLED` 节点
- 并发安全：后端租用接口必须事务锁/行锁，避免重复分配
- 简单公平策略：按 `last_used` 最久未使用优先（均衡磨损）

### 11.2 价格模型
- `PricePlan(region, gpu_tier, billing_unit) -> unit_price`
- 支持 7 个 `gpu_tier`（枚举或配置表），地域可多级（国家/省/机房）
- 计费单位支持：minute/hour/day/week/month（统一取整规则）

## 12. 安全与风控（平台必须项）
- 区分 **设备身份** 与 **用户身份**（不同 token/权限域）
- 所有租赁/释放/重启命令必须后端鉴权与审计
- `lease_token` 高熵、短期有效、与 `lease_id` 绑定；避免泄露后被复用
- 配额与风控（建议）：单用户最大并发租赁数、余额不足限制、异常频繁租赁限制

## 13. 可观测性与运维
建议最少实现：
- 节点心跳与在线判定、离线告警
- 租赁关键指标：ready 耗时、掉线率、平均时长、分配失败原因
- 审计日志：租用/释放/强制操作/重启

## 14. 测试与验收（端到端用例）
必须通过的验收：
1) 节点上线进入 `FREE`，资源池可见（不计费）
2) 用户租用（单台/多台）-> 节点收到 `lease_assigned` -> 回 `lease_ready` -> 后端开始计费
3) 用户远控连接 -> 中途断开 -> 不释放：计费继续
4) 用户释放：后端立即停止计费并生成账单 -> 节点断会话 -> 强制重启 -> 节点重连回 `FREE`
5) 租赁中节点掉线：后端立即停止计费并结算（end_reason=NODE_OFFLINE）
6) 多计费单位：分钟/小时/天/周/月按统一取整规则结算正确
7) 多地域+7档 GPU 定价：选择不同组合后价格正确、调度正确

## 15. 里程碑拆解（建议按可交付闭环推进）
### M0：整理与契约（1–2 周）
- 完成数据模型、状态机、REST/WS 协议文档与字段对齐
- 明确自然月计费口径（半开区间 + 固定账务时区）

### M1：最小闭环（2–4 周）
- 后端：资源池 + rent/release + ready + offline 结算
- 节点：处理 assigned/ready/release；实现 Windows 系统强制重启
- 客户端：资源池租用/我的租赁/释放/进入远控（自动带 lease_token）

### M2：Admin 控制台与运营能力（2–4 周）
- Admin 节点总览、禁用/维护、强制释放/重启
- 账单页完善、审计日志

### M3：增强与规模化（持续迭代）
- 更丰富调度策略、配额/风控、监控告警、导出报表、灰度升级
