# Web v1.3.1-beta 版本说明（新增 RTT 延迟显示）

## 基本信息

- 版本号：`v1.3.1-beta`
- 构建号：`20260102031312`
- 线上站点（Nginx root）：`/var/www/cloudplayplus/web`
- 实际发布目录：`/var/www/cloudplayplus/web_cp_1.3.1-beta_stats_20260102_031312`
- 上一版本回滚指针：`/var/www/cloudplayplus/web_prev_20260102_031312`（指向切换前的目录）

## 变更摘要

本版本在不改变 `v1.3.0` 既有功能（算力池/我的租赁/计费/设置等 UI 与逻辑保持不动）的前提下，仅新增一项调试能力：

- 在 **Web 端远程连接成功后的页面顶部**，展示 WebRTC 串流的实时统计信息，重点为 **RTT（往返时延）**。

## RTT 显示说明

- RTT 数据来源：浏览器 `RTCPeerConnection.getStats()` 报告中的 `candidate-pair`（`state=succeeded` 且 `nominated=true`）项的 `currentRoundTripTime`。
- 单位换算：`currentRoundTripTime` 为秒（s），页面显示为毫秒（ms）。
- 显示条件：检测到已建立连接的 `RTCPeerConnection`，且存在视频流 `inbound-rtp(video)` 时开始显示；未连接/未发现视频流时自动隐藏。

## 实现方式（确保不破坏原有 Web）

为避免重新 `flutter build web` 导致线上 UI/功能偏离 `v1.3.0`，本版本采用“静态注入”方案：

- 在 `index.html` 中于 `flutter_bootstrap.js` 之前注入：`webrtc_stats_overlay.js`
- `webrtc_stats_overlay.js` 通过包装 `window.RTCPeerConnection` 追踪 PeerConnection，并以固定频率轮询 `getStats()`，计算并展示：
  - RTT（核心指标）
  - 接收码率（基于 `bytesReceived` 增量估算）
  - 帧率（基于 `framesDecoded` 增量估算）
  - 分辨率（`frameWidth`/`frameHeight`）
  - 丢包率（`packetsLost`/`packetsReceived` 估算）
- 为避免旧站点被 Service Worker 缓存“劫持”，发布目录自带一个清缓存的 kill-switch：`flutter_service_worker.js`（激活后清空 CacheStorage 并自注销）。

## 验证方式

1. 打开 Web 远程控制并成功连上后，页面顶部应出现统计条，包含 RTT（ms）。
2. 服务器上确认版本号：
   - `cat /var/www/cloudplayplus/web/version.json`

## 回滚方式

如需回滚到切换前版本：

```bash
ln -sfn /var/www/cloudplayplus/web_prev_20260102_031312 /var/www/cloudplayplus/web
```

