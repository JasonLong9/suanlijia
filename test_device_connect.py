import asyncio
import websockets
import requests
import json

BASE_URL = "http://127.0.0.1:8000"
WS_URL = "ws://127.0.0.1:8000/ws/"

def get_token():
    url = f"{BASE_URL}/api/device/token/"
    data = {
        "device_id": "N002",
        "device_secret": "secret123"
    }
    print(f"Requesting token from {url}...")
    try:
        resp = requests.post(url, json=data)
        print(f"Response status: {resp.status_code}")
        if resp.status_code == 200:
            return resp.json().get("device_token")
        else:
            print(f"Response body: {resp.text}")
    except Exception as e:
        print(f"Error getting token: {e}")
    return None

async def test_ws(token):
    uri = f"{WS_URL}?token={token}"
    print(f"Connecting to {uri}...")
    try:
        async with websockets.connect(uri) as websocket:
            print("Connected!")
            msg = await websocket.recv()
            print(f"Received: {msg}")
            
            # Send hello
            hello = {
                "type": "node_hello",
                "data": {
                    "region": "test-region",
                    "gpu_tier": "test-gpu",
                    "agent_version": "0.9.7",
                    "capabilities": {"city": "TestCity"}
                }
            }
            await websocket.send(json.dumps(hello))
            print("Sent hello")
            
            # Keep alive for a bit
            await asyncio.sleep(2)
            print("Closing...")
    except Exception as e:
        print(f"WS Error: {e}")

async def main():
    token = get_token()
    if token:
        print(f"Got token: {token[:20]}...")
        await test_ws(token)
    else:
        print("Failed to get token")

if __name__ == "__main__":
    asyncio.run(main())
