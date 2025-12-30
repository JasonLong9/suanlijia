# 线A：Django 控制平面开发计划（纳管 / 调度 / 计费 / 定价 / Admin）

## 0. 目标与边界
**目标**：在不改动现有 WebRTC/P2P 串流主链路的前提下，新增“控制平面（Control Plane）”，把 Windows GPU 服务器纳入资源池，实现租赁、计费、回收（强制重启）与超级管理员全局管理。

**边界/约束**
- GPU 节点：Windows + 无盘系统（无需镜像/实例交付，只需可重启并回到可用态）
- **开始计费**：节点回 `lease_ready`（租赁就绪）才开始
- **停止计费**：
  - 用户点击释放：后端**立即**停止计费并结算，然后通知节点回收并强制重启
  - 节点掉线：后端立即停止计费并结算（异常结束）
- 远控断开不停止计费（只有 release/offline 才停）
- 计费单位：minute/hour/day/week/**month（自然月）**；不足 1 单位按 1 单位

## 1. 分离协作策略（推荐）
为支持线B（客户端/节点）并行开发，采用 **Contract-first**：
- `contracts/openapi.yaml`：REST 契约（字段/状态/错误码/幂等键）
- `contracts/ws-schema.md`：WebSocket 消息契约（type/data 结构、方向、示例）
- 变更规则：只增不改/兼容优先；破坏性变更必须 bump 版本并保留旧字段一段时间

## 2. 数据模型（建议）
### 2.1 Node（GPU 节点）
- `device_id`（稳定唯一）、`connection_id`（在线会话，可变）
- `region`、`gpu_tier`（7 档规格）
- `status`：OFFLINE/FREE/ASSIGNED/IN_USE/RELEASING/DISABLED/MAINTENANCE
- `last_seen`、`agent_version`、（可选）硬件信息与能力

### 2.2 Lease（租赁单）
- `lease_id`、`user_id`、`device_id`
- `status`：PENDING/ASSIGNED/READY/ACTIVE/RELEASING/ENDED
- `assigned_at/started_at/ended_at`、`end_reason`
- `billing_unit`、`unit_price`、`billed_units`、`amount`
- `lease_token`（高熵一次性连接密钥，用于远控授权/自动密码）

### 2.3 PricePlan（定价）
`(region, gpu_tier, billing_unit) -> unit_price`

### 2.4 BillingRecord + AuditLog
- Billing：结算明细（租赁、单价、单位数、金额、原因）
- Audit：管理员/用户/系统触发的关键操作（租用/释放/掉线/强制）

## 3. 计费引擎（重点：自然月）
### 3.1 通用规则
- 不足 1 单位按 1 单位
- `ended_at` 采用半开区间 `[started_at, ended_at)`（end 不计入）避免边界双计
- 释放：`ended_at = now` 后立即结算（与节点重启完成无关）
- 掉线：`ended_at = offline_detected_at` 立即结算

### 3.2 单位计算
- minute/hour/day/week：按秒数取整（60/3600/86400/604800）
- **month（自然月）**：按日历月边界取整
  - `billed_months = months_between(YearMonth(started_at), YearMonth(ended_at - ε)) + 1`
  - 账务时区必须固定（建议 `Asia/Shanghai` 或按业务要求配置），全链路统一

## 4. WebSocket（节点纳管 + 租赁控制）
建议沿用现有消息包络：`{"type": "...", "data": {...}}`，并通过 token 区分用户连接与设备连接。

### 4.1 设备侧（Node Agent）
**设备 -> 服务端**
- `node_hello`：节点上线注册（device_id/region/gpu_tier/agent_version/可选硬件信息）
- `node_heartbeat`：心跳（device_id、timestamp，可带轻量健康信息）
- `lease_ready`：租赁就绪（lease_id、device_id、timestamp）

**服务端 -> 设备**
- `lease_assigned`：分配租赁（lease_id、lease_token、billing_unit、可选租赁配置）
- `lease_release`：释放回收（lease_id、reason=USER_RELEASE/ADMIN_FORCE_RELEASE）

### 4.2 用户侧（Client）
**服务端 -> 用户**
- `pool_update`：资源池变更（全量或增量）
- `lease_update`：租赁状态变化（READY/ACTIVE/RELEASING/ENDED + 费用与原因）

**用户 -> 服务端**
- `requestRemoteControlLease`：发起远控请求（lease_id + settings）
  - 服务端校验 lease 归属与有效性后，才转发到节点（复用现有串流信令通路）

## 5. REST API（最小闭环优先）
### 5.1 用户 API
- `GET /api/pool/nodes`：按 `region/gpu_tier/status` 查询资源池（附带价格）
- `POST /api/lease/rent`：租用（支持 `count` 多台；返回 leases 列表）
- `POST /api/lease/release`：释放（幂等；支持批量）
- `GET /api/billing/info`：余额/当前租赁/历史账单

### 5.2 设备 API
- `POST /api/device/token`：设备身份换取 `device_token`（device_id + device_secret/签名）

### 5.3 Admin API
- `GET /api/admin/nodes`：全量节点视图（含占用与心跳）
- `POST /api/admin/nodes/{device_id}/state`：disabled/maintenance 切换
- `POST /api/admin/leases/{lease_id}/force_release`：强制释放（立即停费结算 + 下发 release）
- `POST /api/admin/nodes/{device_id}/reboot`：强制重启（不改变计费规则，仅运维）

## 6. 调度与并发（必须保证不重复分配）
### 6.1 调度输入
- `region`、`gpu_tier`、`count`、`billing_unit`

### 6.2 并发控制建议
- `rent` 使用数据库事务 + 行锁（如 `SELECT ... FOR UPDATE SKIP LOCKED`）挑选 `FREE` 节点
- 节点状态变更必须可重放（幂等），避免重复 ready/release 导致状态错乱

## 7. 关键流程（后端视角）
### 7.1 Rent
1) 校验用户余额/配额（可先跳过，后续补）
2) 事务内挑选 `FREE` 节点 -> 创建 `Lease(status=ASSIGNED)` -> 更新 Node=ASSIGNED
3) 生成 `lease_token` 并通过 WS 下发 `lease_assigned`
4) 返回租赁单（客户端进入“准备中”）

### 7.2 Ready（开始计费）
1) 收到 `lease_ready` -> 校验 lease 状态与 device 匹配
2) 记录 `started_at`，Lease=ACTIVE，Node=IN_USE
3) 推送 `lease_update` 给用户

### 7.3 Release（立即停费 + 回收重启）
1) 用户 release：幂等写入 `ended_at=now` + 结算（billed_units 取整）
2) Lease=ENDED（或 RELEASING->ENDED，取决于是否要等待回执；建议直接 ENDED，重启异步）
3) WS 下发 `lease_release` 给节点（节点会断会话并系统重启）
4) 节点掉线/重连后，Node 回到 `FREE`（可加“冷却时间”）

### 7.4 Offline（异常停费）
1) 设备 WS 断开/心跳超时 -> Node=OFFLINE
2) 若存在 ACTIVE 租赁：立即 `ended_at=offline_time` + 结算，Lease=ENDED(end_reason=NODE_OFFLINE)
3) 推送 `lease_update` 给用户与审计

## 8. 远控授权（与现有 P2P 兼容的关键点）
现有系统偏“同账号设备互控”，资源池必须引入授权校验：
- 远控请求必须绑定租赁（lease_id/lease_token），服务端验证通过后才允许转发信令到节点
- 推荐做法：新增 `requestRemoteControlLease` 事件，服务端内部转为现有 `remoteSessionRequested` 流程

## 9. 测试与验收
- 契约测试：OpenAPI + WS schema（字段/错误码/状态机）
- 并发测试：多用户同时 rent，不重复分配
- 计费测试：五种单位 + 取整 + 自然月边界（跨月/整月/月初 00:00）
- 关键 E2E：rent→ready→远控→断开不停费→release 立刻停费→节点重启→FREE

## 10. 里程碑（建议）
- M0（契约冻结）：contracts 完成 + 关键状态机/计费口径定稿
- M1（最小闭环）：node 纳管 + rent/release + ready + offline 结算 + 基础定价
- M2（Admin）：禁用/维护/强制释放/强制重启 + 审计
- M3（运营增强）：余额/配额/风控 + 监控告警 + 报表导出
