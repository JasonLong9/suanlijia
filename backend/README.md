# CloudPlayPlus 控制平面（Django）本地运行

## 依赖
- Python 3.8+

安装依赖：
```bash
python3 -m pip install -r backend/requirements.txt
```

## 初始化数据库
```bash
python3 backend/manage.py migrate
python3 backend/manage.py createsuperuser
```

## 预置节点与价格（示例）
创建一个节点（用于 `/api/device/token/` 校验）：
```bash
python3 backend/manage.py cp_create_node --device-id node_001 --device-secret dev_secret --region cn-shanghai --gpu-tier tier_7
```

写入示例价格（可重复执行，幂等 upsert）：
```bash
python3 backend/manage.py cp_seed_prices
```

## 启动服务
```bash
python3 backend/manage.py runserver 0.0.0.0:8000
```

- REST API：`http://127.0.0.1:8000/api/...`
- WebSocket：`ws://127.0.0.1:8000/ws/?token=<jwt>`

## Flutter 联调（关键点）
- 用户端：用 `/api/login/` 获取 `access`，WS 用 `?token=<access>` 连接。
- 节点端：用 `/api/device/token/` 获取 `device_token`，WS 用 `?token=<device_token>` 连接；上线后发送 `node_hello`。

## 本地闭环冒烟（可选）
先启动服务，然后运行：
```bash
python3 backend/scripts/e2e_smoke.py
```
