# WebSocket Schema（控制平面）

## 1) 通用包络
平台 WebSocket 消息统一使用：

```json
{
  "type": "message_type",
  "data": {}
}
```

可选字段（推荐，用于排障/幂等/追踪；后端可逐步支持）：
- `msg_id`：消息唯一 ID（UUID）
- `ts`：发送时间（ISO8601）

## 2) 认证与连接
- 建议沿用现有连接方式：`wss://<host>/ws/?token=<jwt>`
- token 域（由后端签发与校验）：
  - `user`：客户
  - `admin`：超级管理员
  - `device`：GPU 节点守护程序

## 3) 设备侧（device token）

### 3.1 device -> server
#### `node_hello`
节点上线注册/刷新基础信息。

```json
{
  "type": "node_hello",
  "data": {
    "device_id": "node_001",
    "region": "cn-shanghai",
    "gpu_tier": "tier_7",
    "agent_version": "1.0.0",
    "capabilities": {
      "max_resolution": "2560x1440",
      "codec": ["h264"]
    }
  }
}
```

#### `node_heartbeat`
节点心跳（建议 5–15s；字段尽量轻量）。

```json
{
  "type": "node_heartbeat",
  "data": {
    "device_id": "node_001",
    "ts": "2025-12-21T12:00:00Z"
  }
}
```

#### `lease_ready`
节点已完成本次租赁准备，服务端从此刻开始计费。

```json
{
  "type": "lease_ready",
  "data": {
    "lease_id": "lease_abc",
    "device_id": "node_001",
    "ts": "2025-12-21T12:01:00Z"
  }
}
```

### 3.2 server -> device
#### `lease_assigned`
服务端分配租赁给节点。

```json
{
  "type": "lease_assigned",
  "data": {
    "lease_id": "lease_abc",
    "device_id": "node_001",
    "lease_token": "high_entropy_secret",
    "billing_unit": "minute"
  }
}
```

#### `lease_release`
释放指令。节点需断开会话并强制重启系统（Windows）。

```json
{
  "type": "lease_release",
  "data": {
    "lease_id": "lease_abc",
    "device_id": "node_001",
    "reason": "USER_RELEASE"
  }
}
```

## 4) 用户侧（user token）

### 4.1 server -> user
#### `pool_update`
资源池更新（可做全量或增量；MVP 可直接全量）。

```json
{
  "type": "pool_update",
  "data": {
    "mode": "full",
    "nodes": [
      {
        "device_id": "node_001",
        "connection_id": "conn_abc_or_null",
        "region": "cn-shanghai",
        "gpu_tier": "tier_7",
        "status": "FREE",
        "last_seen": "2025-12-21T12:00:00Z",
        "agent_version": "0.1.0"
      }
    ]
  }
}
```

#### `lease_update`
租赁状态更新（用于 UI 实时刷新）。

```json
{
  "type": "lease_update",
  "data": {
    "lease": {
      "lease_id": "lease_abc",
      "device_id": "node_001",
      "status": "ACTIVE",
      "billing_unit": "minute",
      "unit_price": 0.5,
      "started_at": "2025-12-21T12:01:00Z",
      "ended_at": null,
      "end_reason": null
    }
  }
}
```

### 4.2 user -> server
#### `requestRemoteControlLease`
用户发起远控请求（服务端必须校验 lease 归属与有效性后，才转发给节点进入既有 P2P 串流流程）。

> `settings` 建议直接复用现有 `StreamingSettings.toJson()` 结构。

```json
{
  "type": "requestRemoteControlLease",
  "data": {
    "lease_id": "lease_abc",
    "settings": {}
  }
}
```

## 5) 状态与错误（建议）
- WS 层错误可通过 `type=error` 返回：

```json
{
  "type": "error",
  "data": {
    "code": "LEASE_NOT_ACTIVE",
    "message": "lease is not active",
    "context": { "lease_id": "lease_abc" }
  }
}
```
