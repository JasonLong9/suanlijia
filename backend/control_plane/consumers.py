import json
import uuid
from dataclasses import dataclass
from typing import Any, Dict, Optional
from urllib.parse import parse_qs

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncWebsocketConsumer
from django.contrib.auth.models import User
from django.db import transaction
from django.utils import timezone

from control_plane.models import Lease, LeaseStatus, Node, NodeStatus
from control_plane.services.auth import authenticate_ws_token
from control_plane.services.lease_lifecycle import (
    end_lease,
    mark_node_offline_and_end_leases,
    push_lease_update,
    push_pool_update,
    serialize_lease,
)


@dataclass
class ConnectionMeta:
    role: str  # "user" | "device"
    user_id: Optional[int] = None
    nickname: str = ""
    device_id: Optional[str] = None
    connection_id: str = ""
    channel_name: str = ""

    # device info (for user device list)
    device_name: str = ""
    device_type: str = ""
    connective: bool = False
    screen_count: int = 1


# In-memory registries (MVP: single-process InMemoryChannelLayer).
_connections: Dict[str, ConnectionMeta] = {}  # connection_id -> meta


def _build_device_list_for_user(user_id: int):
    devices = []
    for meta in _connections.values():
        if meta.role != "user":
            continue
        if meta.user_id == user_id or meta.connective:
            devices.append(
                {
                    "owner_id": meta.user_id,
                    "owner_nickname": meta.nickname,
                    "connection_id": meta.connection_id,
                    "device_type": meta.device_type or "Unknown",
                    "device_name": meta.device_name or "Unknown",
                    "connective": bool(meta.connective),
                    "screen_count": int(meta.screen_count or 1),
                }
            )
    return devices


class ControlPlaneConsumer(AsyncWebsocketConsumer):
    meta: ConnectionMeta

    async def connect(self):
        import sys
        print(f"[WS] connect() called, query_string: {self.scope.get('query_string', b'')}", file=sys.stderr, flush=True)
        
        token = self._get_token()
        print(f"[WS] token extracted: {token[:30] if token else 'EMPTY'}...", file=sys.stderr, flush=True)
        
        if not token:
            print("[WS] REJECT: no token", file=sys.stderr, flush=True)
            await self.close(code=4401)
            return

        auth_result = await database_sync_to_async(authenticate_ws_token)(token)
        print(f"[WS] auth_result: {auth_result}", file=sys.stderr, flush=True)
        
        if auth_result is None:
            print("[WS] REJECT: auth_result is None", file=sys.stderr, flush=True)
            await self.close(code=4401)
            return

        connection_id = uuid.uuid4().hex
        self.meta = ConnectionMeta(
            role=auth_result.role,
            user_id=auth_result.user.id if auth_result.user else None,
            nickname=(auth_result.user.first_name or auth_result.user.username)
            if auth_result.user
            else "node",
            device_id=auth_result.device_id,
            connection_id=connection_id,
            channel_name=self.channel_name,
        )

        await self.accept()

        # register & join groups
        _connections[connection_id] = self.meta
        if self.meta.role == "user":
            await self.channel_layer.group_add("users", self.channel_name)
            await self.channel_layer.group_add(
                f"user_{self.meta.user_id}", self.channel_name
            )
        else:
            await self.channel_layer.group_add(
                f"node_{self.meta.device_id}", self.channel_name
            )
            await self._node_connected(self.meta.device_id, connection_id)

        # send connection_info (client expects it to set AppStateService.websocketSessionid)
        await self.send_json(
            "connection_info",
            {
                "connection_id": connection_id,
                "uid": self.meta.user_id or 0,
                "nickname": self.meta.nickname,
            },
        )

    async def disconnect(self, code):
        meta = getattr(self, "meta", None)
        if meta is None:
            return
        import sys
        try:
            cid = meta.connection_id or ""
            cid_short = f"{cid[:20]}..." if len(cid) > 20 else cid
        except Exception:
            cid_short = ""
        print(
            f"[WS] disconnect role={meta.role} user_id={meta.user_id} device_id={meta.device_id} connection_id={cid_short} code={code}",
            file=sys.stderr,
            flush=True,
        )

        _connections.pop(meta.connection_id, None)

        if meta.role == "user":
            await self.channel_layer.group_discard("users", self.channel_name)
            await self.channel_layer.group_discard(
                f"user_{meta.user_id}", self.channel_name
            )
            await self._broadcast_connected_devices()
        else:
            await self.channel_layer.group_discard(
                f"node_{meta.device_id}", self.channel_name
            )
            await self._node_disconnected(meta.device_id)

    async def receive(self, text_data=None, bytes_data=None):
        import sys
        if not text_data:
            return
        try:
            message = json.loads(text_data)
        except Exception as e:
            print(f"[WS_MSG] JSON parse error: {e}", file=sys.stderr, flush=True)
            return

        msg_type = message.get("type")
        data = message.get("data") or {}
        
        # Log all received messages
        print(f"[WS_MSG] Received: type={msg_type}, from={self.meta.role}:{self.meta.user_id or self.meta.device_id}, data_keys={list(data.keys())}", file=sys.stderr, flush=True)

        if msg_type == "ping":
            await self.send_json("pong", {})
            return

        if msg_type == "updateDeviceInfo":
            await self._handle_update_device_info(data)
            return

        # Control plane: node management
        if msg_type == "node_hello":
            if self.meta.role != "device":
                return
            await self._handle_node_hello(data)
            return

        if msg_type == "node_heartbeat":
            if self.meta.role != "device":
                return
            await self._handle_node_heartbeat(data)
            return

        if msg_type == "lease_ready":
            if self.meta.role != "device":
                return
            await self._handle_lease_ready(data)
            return

        # Control plane: lease-authorized streaming
        if msg_type == "requestRemoteControlLease":
            if self.meta.role != "user":
                return
            await self._handle_request_remote_control_lease(data)
            return

        # Legacy P2P signaling
        if msg_type in ("requestRemoteControl", "offer", "answer", "candidate", "candidate2"):
            await self._handle_signaling(msg_type, data)
            return

        # Client logs
        if msg_type == "client_log":
            await self._handle_client_log(data)
            return

        # Unknown messages are ignored for MVP.

    async def ws_send(self, event):
        import sys
        text = event.get("text", "")
        import json
        try:
            msg = json.loads(text)
            print(f"[WS_SEND] Sending to {self.meta.role}:{self.meta.user_id or self.meta.device_id}, type={msg.get('type')}", file=sys.stderr, flush=True)
        except:
            pass
        await self.send(text_data=text)


    # -------- helpers --------
    def _get_token(self) -> str:
        try:
            query = self.scope.get("query_string", b"").decode("utf-8")
        except Exception:
            query = ""
        
        # Remove leading ? if present (some WebSocket implementations include it)
        if query.startswith("?"):
            query = query[1:]
        
        qs = parse_qs(query)
        token_list = qs.get("token")
        if not token_list:
            return ""
        return token_list[0] or ""

    async def send_json(self, msg_type: str, data: Dict[str, Any]):
        await self.send(text_data=json.dumps({"type": msg_type, "data": data}))

    async def send_error(self, code: str, message: str, context: Optional[Dict[str, Any]] = None):
        payload = {"code": code, "message": message}
        if context is not None:
            payload["context"] = context
        await self.send_json("error", payload)

    async def _broadcast_connected_devices(self):
        user_ids = {m.user_id for m in _connections.values() if m.role == "user" and m.user_id}
        for uid in user_ids:
            devices = _build_device_list_for_user(uid)
            await self.channel_layer.group_send(
                f"user_{uid}",
                {
                    "type": "ws.send",
                    "text": json.dumps({"type": "connected_devices", "data": devices}),
                },
            )

    async def _handle_update_device_info(self, data: Dict[str, Any]):
        self.meta.device_name = str(data.get("deviceName") or "")
        self.meta.device_type = str(data.get("deviceType") or "")
        self.meta.connective = bool(data.get("connective") or False)
        self.meta.screen_count = int(data.get("screenCount") or 1)

        if self.meta.role == "user":
            await self._broadcast_connected_devices()
        else:
            # Node is not part of connected_devices; just keep DB last_seen fresh.
            await self._node_touch_last_seen(self.meta.device_id)

    # -------- node management --------
    @database_sync_to_async
    def _node_connected(self, device_id: str, connection_id: str):
        import sys
        print(f"[NODE_CONN] _node_connected called: device_id={device_id}, connection_id={connection_id[:20]}...", file=sys.stderr, flush=True)
        now = timezone.now()
        node, _ = Node.objects.get_or_create(device_id=device_id)
        node.connection_id = connection_id
        node.last_seen = now
        if node.status not in (NodeStatus.DISABLED, NodeStatus.MAINTENANCE):
            # If no active lease, node becomes FREE on connect.
            active = Lease.objects.filter(
                device=node,
                status__in=[
                    LeaseStatus.ASSIGNED,
                    LeaseStatus.READY,
                    LeaseStatus.ACTIVE,
                    LeaseStatus.RELEASING,
                ],
            ).exists()
            if not active:
                node.status = NodeStatus.FREE
        node.save(update_fields=["connection_id", "last_seen", "status", "updated_at"])
        print(f"[NODE_CONN] Database updated: connection_id={node.connection_id[:20]}..., status={node.status}", file=sys.stderr, flush=True)


    async def _node_disconnected(self, device_id: str):
        await database_sync_to_async(mark_node_offline_and_end_leases)(device_id=device_id)

    @database_sync_to_async
    def _node_touch_last_seen(self, device_id: str):
        now = timezone.now()
        Node.objects.filter(device_id=device_id).update(last_seen=now, updated_at=now)

    async def _handle_node_hello(self, data: Dict[str, Any]):
        await self._update_node_hello(
            device_id=self.meta.device_id,
            region=str(data.get("region") or ""),
            gpu_tier=str(data.get("gpu_tier") or ""),
            agent_version=str(data.get("agent_version") or ""),
            capabilities=data.get("capabilities"),
        )
        await database_sync_to_async(push_pool_update)()

    @database_sync_to_async
    def _update_node_hello(self, *, device_id: str, region: str, gpu_tier: str, agent_version: str, capabilities):
        now = timezone.now()
        node, _ = Node.objects.get_or_create(device_id=device_id)
        node.region = region or node.region
        node.gpu_tier = gpu_tier or node.gpu_tier
        node.agent_version = agent_version or node.agent_version
        node.capabilities = capabilities if capabilities is not None else node.capabilities
        node.last_seen = now
        
        # Transition to FREE if OFFLINE or RELEASING and no active leases
        if node.status in (NodeStatus.OFFLINE, NodeStatus.RELEASING):
            active = Lease.objects.filter(
                device=node,
                status__in=[
                    LeaseStatus.ASSIGNED,
                    LeaseStatus.READY,
                    LeaseStatus.ACTIVE,
                    LeaseStatus.RELEASING,
                ],
            ).exists()
            if not active:
                node.status = NodeStatus.FREE
                
        node.save(update_fields=["region", "gpu_tier", "agent_version", "capabilities", "last_seen", "status", "updated_at"])

    async def _handle_node_heartbeat(self, data: Dict[str, Any]):
        await self._node_touch_last_seen(self.meta.device_id)

    async def _handle_lease_ready(self, data: Dict[str, Any]):
        lease_id = data.get("lease_id")
        device_id = data.get("device_id") or self.meta.device_id
        if not lease_id or not device_id:
            return
        lease = await self._mark_lease_ready(lease_id=str(lease_id), device_id=str(device_id))
        if lease is None:
            return
        await database_sync_to_async(push_lease_update)(lease)
        await database_sync_to_async(push_pool_update)()

    @database_sync_to_async
    def _mark_lease_ready(self, *, lease_id: str, device_id: str) -> Optional[Lease]:
        now = timezone.now()
        with transaction.atomic():
            lease = Lease.objects.select_for_update().filter(lease_id=lease_id).first()
            if lease is None:
                return None
            if lease.device_id != device_id:
                return None
            if lease.status not in (LeaseStatus.ASSIGNED, LeaseStatus.READY, LeaseStatus.ACTIVE):
                return lease

            if lease.started_at is None:
                lease.started_at = now
            lease.status = LeaseStatus.READY
            lease.save(update_fields=["started_at", "status", "updated_at"])

            node = Node.objects.select_for_update().filter(device_id=device_id).first()
            if node is not None and node.status not in (NodeStatus.DISABLED, NodeStatus.MAINTENANCE):
                node.status = NodeStatus.IN_USE
                node.last_seen = now
                node.save(update_fields=["status", "last_seen", "updated_at"])
        return lease

    # -------- lease-authorized streaming --------
    async def _handle_request_remote_control_lease(self, data: Dict[str, Any]):
        import sys
        print(f"[LEASE_STREAM] Processing requestRemoteControlLease from user:{self.meta.user_id}", file=sys.stderr, flush=True)
        
        lease_id = data.get("lease_id")
        settings_obj = data.get("settings") or {}
        if not lease_id:
            print(f"[LEASE_STREAM] ERROR: missing lease_id", file=sys.stderr, flush=True)
            await self.send_error("BAD_REQUEST", "missing lease_id")
            return

        print(f"[LEASE_STREAM] Authorizing lease: {lease_id}", file=sys.stderr, flush=True)
        result = await self._authorize_lease_stream(
            lease_id=str(lease_id),
            user_id=self.meta.user_id,
        )
        if result is None:
            print(f"[LEASE_STREAM] ERROR: lease not found or not authorized", file=sys.stderr, flush=True)
            await self.send_error("LEASE_NOT_FOUND", "lease not found", {"lease_id": lease_id})
            return

        node_device_id, node_connection_id, lease = result
        print(f"[LEASE_STREAM] Lease authorized. device_id={node_device_id}, connection_id={node_connection_id[:20] if node_connection_id else None}...", file=sys.stderr, flush=True)
        
        if not node_connection_id:
            print(f"[LEASE_STREAM] ERROR: node offline (no connection_id)", file=sys.stderr, flush=True)
            await self.send_error("NODE_OFFLINE", "node offline", {"device_id": node_device_id})
            return

        # move lease READY -> ACTIVE when user actually starts remote control
        if lease.status == LeaseStatus.READY:
            lease = await self._set_lease_active(lease_id=str(lease.lease_id))
            await database_sync_to_async(push_lease_update)(lease)

        # Sanitize settings to ensure types match what Dart expects
        if settings_obj:
            # Ensure connectPassword is a string
            if "connectPassword" in settings_obj:
                settings_obj["connectPassword"] = str(settings_obj["connectPassword"])
            # Ensure streamMode is an int
            if "streamMode" in settings_obj and settings_obj["streamMode"] is not None:
                try:
                    settings_obj["streamMode"] = int(settings_obj["streamMode"])
                except:
                    settings_obj.pop("streamMode")
            # Ensure other int fields
            for key in ["framerate", "bitrate", "audioBitrate", "targetScreenId", "customScreenWidth", "customScreenHeight"]:
                if key in settings_obj and settings_obj[key] is not None:
                    try:
                        settings_obj[key] = int(settings_obj[key])
                    except:
                        settings_obj.pop(key)

        requester_info = {
            "owner_id": int(self.meta.user_id or 0), # Ensure int
            "owner_nickname": str(self.meta.nickname or ""), # Ensure string
            "connection_id": str(self.meta.connection_id), # Ensure string
            "device_type": str(self.meta.device_type or "Unknown"), # Ensure string
            "device_name": str(self.meta.device_name or "Unknown"), # Ensure string
            "connective": True,
            "screen_count": int(self.meta.screen_count or 1), # Ensure int
        }

        # Use group_send to node_{device_id} group.
        print(f"[LEASE_STREAM] Sending remoteSessionRequested to node group: node_{node_device_id}", file=sys.stderr, flush=True)
        print(f"[LEASE_STREAM] Payload settings: {settings_obj}", file=sys.stderr, flush=True)
        
        # IMPORTANT: Flutter client (WebSocketService.onMessage) expects the standard envelope:
        # {"type": "...", "data": {"requester_info": {...}, "settings": {...}}}
        # Keep top-level requester_info/settings as backward-compatible extras.
        await self.channel_layer.group_send(
            f"node_{node_device_id}",
            {
                "type": "ws.send",
                "text": json.dumps({
                    "type": "remoteSessionRequested",
                    "data": {
                        "requester_info": requester_info,
                        "settings": settings_obj,
                    },
                    "requester_info": requester_info,
                    "settings": settings_obj,
                }),
            },
        )
        print(f"[LEASE_STREAM] remoteSessionRequested sent to group successfully", file=sys.stderr, flush=True)





    @database_sync_to_async
    def _authorize_lease_stream(self, *, lease_id: str, user_id: int):
        lease = Lease.objects.select_related("device").filter(lease_id=lease_id, user_id=user_id).first()
        if lease is None:
            return None
        if lease.status not in (LeaseStatus.READY, LeaseStatus.ACTIVE):
            return None
        node = lease.device
        return node.device_id, node.connection_id, lease

    @database_sync_to_async
    def _set_lease_active(self, *, lease_id: str) -> Lease:
        lease = Lease.objects.get(lease_id=lease_id)
        lease.status = LeaseStatus.ACTIVE
        lease.save(update_fields=["status", "updated_at"])
        return lease

    # -------- signaling routing --------
    async def _handle_signaling(self, msg_type: str, data: Dict[str, Any]):
        if msg_type == "requestRemoteControl":
            await self._handle_request_remote_control(data)
            return

        target_connectionid = data.get("target_connectionid")
        if not target_connectionid:
            return

        # Controller -> Node may address by stable device_id (lease mode)
        target_connection_id_resolved = await self._resolve_target_connection_id(str(target_connectionid))
        if not target_connection_id_resolved:
            return

        outgoing = dict(data)

        # Node -> Controller (lease mode): rewrite source_connectionid to stable device_id so
        # controller side can key sessions by device_id.
        if msg_type in ("offer", "candidate") and self.meta.role == "device":
            outgoing["source_connectionid"] = self.meta.device_id

        await self._send_to_connection(target_connection_id_resolved, msg_type, outgoing)

    async def _handle_request_remote_control(self, data: Dict[str, Any]):
        # Legacy: controller asks server to send "remoteSessionRequested" to target connection.
        target_connectionid = data.get("target_connectionid")
        settings_obj = data.get("settings") or {}
        if not target_connectionid:
            return
        target_connection_id_resolved = await self._resolve_target_connection_id(str(target_connectionid))
        if not target_connection_id_resolved:
            return

        requester_info = {
            "owner_id": self.meta.user_id or 0,
            "owner_nickname": self.meta.nickname,
            "connection_id": self.meta.connection_id,
            "device_type": self.meta.device_type or "Unknown",
            "device_name": self.meta.device_name or "Unknown",
            "connective": True,
            "screen_count": self.meta.screen_count or 1,
        }

        await self._send_to_connection(
            target_connection_id_resolved,
            "remoteSessionRequested",
            {"requester_info": requester_info, "settings": settings_obj},
        )

    async def _resolve_target_connection_id(self, identifier: str) -> Optional[str]:
        # identifier may be an actual connection_id, or a node device_id.
        if identifier in _connections:
            return identifier
        return await self._lookup_node_connection_id(identifier)

    @database_sync_to_async
    def _lookup_node_connection_id(self, device_id: str) -> Optional[str]:
        node = Node.objects.filter(device_id=device_id).first()
        if node is None or not node.connection_id:
            return None
        return node.connection_id

    async def _send_to_connection(self, connection_id: str, msg_type: str, data: Dict[str, Any]):
        import sys
        meta = _connections.get(connection_id)
        if meta is None:
            print(f"[SEND_CONN] ERROR: connection_id {connection_id[:20]}... NOT FOUND in _connections!", file=sys.stderr, flush=True)
            print(f"[SEND_CONN] Available connections: {list(_connections.keys())}", file=sys.stderr, flush=True)
            return
        print(f"[SEND_CONN] Sending {msg_type} to {connection_id[:20]}... (channel: {meta.channel_name})", file=sys.stderr, flush=True)
        await self.channel_layer.send(
            meta.channel_name,
            {
                "type": "ws.send",
                "text": json.dumps({"type": msg_type, "data": data}),
            },
        )

    async def _handle_client_log(self, data: Dict[str, Any]):
        import sys
        import os
        from django.conf import settings
        
        message = data.get("message", "")
        level = data.get("level", "INFO")
        device_id = self.meta.device_id or "unknown"
        user_id = self.meta.user_id or "unknown"
        
        log_entry = f"[{timezone.now()}] [{device_id}] [{user_id}] [{level}] {message}\n"
        
        # Print to stderr for immediate visibility
        print(f"[CLIENT_LOG] {log_entry.strip()}", file=sys.stderr, flush=True)
        
        # Write to file
        try:
            log_dir = settings.BASE_DIR / "logs"
            if not os.path.exists(log_dir):
                os.makedirs(log_dir)
            
            with open(log_dir / "client_logs.log", "a", encoding="utf-8") as f:
                f.write(log_entry)
        except Exception as e:
            print(f"[CLIENT_LOG] Error writing to file: {e}", file=sys.stderr, flush=True)
