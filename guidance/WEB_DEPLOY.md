# Web（资源池/租赁）安全发布/回滚指南

本指南针对你们当前正在使用的“旧版 Web（含资源池/我的租赁/设置 + 远控）”。

## 关键约定（防止再次“覆盖丢站”）

- **永远不要**把 `build/web` 直接 `cp -r` 覆盖到 `/var/www/cloudplayplus/web`。
- `/var/www/cloudplayplus/web` 必须保持为 **软链接**，指向某个“不可变发布目录”。
- 每次发布都生成一个新目录（带版本号/时间戳），然后 **原子切换软链接**；出问题就 **一键回滚**。

目录结构（示例）：

- 当前生效：`/var/www/cloudplayplus/web` → `/var/www/cloudplayplus/web_cp_<version>_<build>_<ts>`
- 历史回滚点：`/var/www/cloudplayplus/web_prev_<ts>` → 上一个生效目录

> Nginx（8080）root 固定指向：`/var/www/cloudplayplus/web`（软链），不要改成具体目录。

## 发布（推荐唯一方式）

在项目目录 `/SuanLiJia` 执行：

```bash
bash scripts/deploy_web_controlplane.sh <version> [build_number]
```

例子：

```bash
bash scripts/deploy_web_controlplane.sh 2.0.0
```

这个脚本会做：

- `flutter build web --release`（默认 `--pwa-strategy=none`）
- 校验构建产物必须包含：
  - `/api/pool/nodes/`
  - `/api/lease/list/`
  - `/api/billing/info/`
  - `requestRemoteControlLease`
  - `| RTT`（顶部统计栏）
- 生成发布目录：`/var/www/cloudplayplus/web_cp_<version>_<build>_<ts>`
- 自动保存回滚点：`/var/www/cloudplayplus/web_prev_<ts>`
- 原子切换：`/var/www/cloudplayplus/web` → 新目录
- reload：`/usr/local/nginx`

## 验证（上线后 30 秒内必须做）

1) 先看版本号是否已切换：

```bash
wget -qO- http://<server-ip>:8080/version.json
```

2) 浏览器端如果仍显示旧页面：

- 先打开 `http://<server-ip>:8080/version.json` 确认版本已变
- 再用无痕窗口访问主页
- 或 DevTools → Application → Service Workers：Unregister
- 再 DevTools → Application → Storage：Clear site data

## 回滚（出问题立即执行）

```bash
bash scripts/rollback_web.sh /var/www/cloudplayplus/web_prev_<ts>
```

回滚后同样用 `http://<server-ip>:8080/version.json` 确认版本恢复。
