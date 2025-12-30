import json

# 用户的 node.json 内容
node_json_text = '''{
  "enabled": true,
  "device_id": "N001",
  "device_secret": "N001_65751",
  "region": "cn",
  "city": "Chengde",
  "gpu_tier": "tier_7",
  "heartbeat_seconds": 10,
  "agent_version": "0.9.6",
  "reboot_on_release": true,
  "reboot_delay_seconds": 3,
  "public_ip": "61.182.4.90",
  "hostname": "N001"
}'''

try:
    decoded = json.loads(node_json_text)
    print("✅ JSON 解析成功!")
    print(f"enabled: {decoded.get('enabled')}")
    print(f"device_id: {decoded.get('device_id')}")
    print(f"device_secret: {decoded.get('device_secret')}")
except Exception as e:
    print(f"❌ JSON 解析失败: {e}")
