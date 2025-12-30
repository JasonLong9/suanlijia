import asyncio
import json
import os
import time
from urllib.parse import urlencode

import requests
import websockets


BASE = os.environ.get("CP_BASE_URL", "http://127.0.0.1:8000")
WS = os.environ.get("CP_WS_URL", "ws://127.0.0.1:8000/ws/")

DEVICE_ID = os.environ.get("CP_DEVICE_ID", "node_001")
DEVICE_SECRET = os.environ.get("CP_DEVICE_SECRET", "dev_secret")
REGION = os.environ.get("CP_REGION", "cn-shanghai")
GPU_TIER = os.environ.get("CP_GPU_TIER", "tier_7")


def post(path: str, payload: dict):
    return requests.post(BASE + path, json=payload)


def post_auth(path: str, payload: dict, access: str):
    return requests.post(
        BASE + path, json=payload, headers={"Authorization": f"Bearer {access}"}
    )


async def ws_recv_until(ws, want_types, timeout=20):
    end = time.time() + timeout
    while time.time() < end:
        msg = await asyncio.wait_for(ws.recv(), timeout=end - time.time())
        data = json.loads(msg)
        if data.get("type") in want_types:
            return data
    raise TimeoutError(f"no message in {want_types}")


async def main():
    suffix = str(int(time.time()))
    username = f"smoke_{suffix}"
    password = "p12345678"

    # best-effort register
    post(
        "/api/register/",
        {
            "username": username,
            "password": password,
            "email": f"{username}@example.com",
            "nickname": "Smoke",
        },
    )

    login = post("/api/login/", {"username": username, "password": password})
    login.raise_for_status()
    access = login.json()["access"]

    device = post(
        "/api/device/token/",
        {"device_id": DEVICE_ID, "device_secret": DEVICE_SECRET},
    )
    device.raise_for_status()
    device_token = device.json()["device_token"]

    user_ws = await websockets.connect(WS + "?" + urlencode({"token": access}))
    node_ws = await websockets.connect(WS + "?" + urlencode({"token": device_token}))

    await ws_recv_until(user_ws, {"connection_info"})
    await ws_recv_until(node_ws, {"connection_info"})

    await user_ws.send(
        json.dumps(
            {
                "type": "updateDeviceInfo",
                "data": {
                    "deviceName": "smoke-web",
                    "deviceType": "Web",
                    "connective": True,
                    "screenCount": 1,
                },
            }
        )
    )

    await node_ws.send(
        json.dumps(
            {
                "type": "updateDeviceInfo",
                "data": {
                    "deviceName": DEVICE_ID,
                    "deviceType": "Windows",
                    "connective": False,
                    "screenCount": 1,
                },
            }
        )
    )

    await node_ws.send(
        json.dumps(
            {
                "type": "node_hello",
                "data": {
                    "device_id": DEVICE_ID,
                    "region": REGION,
                    "gpu_tier": GPU_TIER,
                    "agent_version": "smoke",
                },
            }
        )
    )

    rent = post_auth(
        "/api/lease/rent/",
        {
            "region": REGION,
            "gpu_tier": GPU_TIER,
            "billing_unit": "minute",
            "count": 1,
            "client_request_id": f"smoke-rent-{suffix}",
        },
        access,
    )
    rent.raise_for_status()
    lease_id = rent.json()["leases"][0]["lease_id"]

    await ws_recv_until(node_ws, {"lease_assigned"})
    await ws_recv_until(user_ws, {"lease_update"})  # ASSIGNED

    await node_ws.send(
        json.dumps({"type": "lease_ready", "data": {"lease_id": lease_id, "device_id": DEVICE_ID}})
    )
    await ws_recv_until(user_ws, {"lease_update"})  # READY

    await user_ws.send(
        json.dumps(
            {
                "type": "requestRemoteControlLease",
                "data": {"lease_id": lease_id, "settings": {"bitrate": 80000, "framerate": 60}},
            }
        )
    )
    await ws_recv_until(node_ws, {"remoteSessionRequested"})

    release = post_auth(
        "/api/lease/release/",
        {"lease_ids": [lease_id], "client_request_id": f"smoke-rel-{suffix}"},
        access,
    )
    release.raise_for_status()
    await ws_recv_until(node_ws, {"lease_release"})

    await user_ws.close()
    await node_ws.close()
    print("SMOKE_OK")


if __name__ == "__main__":
    asyncio.run(main())

