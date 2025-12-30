import json
from typing import Any, Dict

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer


def send_ws(group: str, message_type: str, data: Dict[str, Any]) -> None:
    channel_layer = get_channel_layer()
    async_to_sync(channel_layer.group_send)(
        group,
        {
            "type": "ws.send",
            "text": json.dumps({"type": message_type, "data": data}),
        },
    )


def send_ws_many(groups, message_type: str, data: Dict[str, Any]) -> None:
    for group in groups:
        send_ws(group, message_type, data)

