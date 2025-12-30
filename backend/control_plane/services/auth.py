from typing import Optional, Tuple
import sys

import jwt
from django.conf import settings
from django.contrib.auth.models import User
from rest_framework_simplejwt.authentication import JWTAuthentication


class WsAuthResult:
    def __init__(self, *, role: str, user: Optional[User] = None, device_id: Optional[str] = None):
        self.role = role
        self.user = user
        self.device_id = device_id


def authenticate_ws_token(token: str) -> Optional[WsAuthResult]:
    print(f"[WS_AUTH] Authenticating token: {token[:30]}...", file=sys.stderr, flush=True)
    
    # 1) Try SimpleJWT user token
    auth = JWTAuthentication()
    try:
        validated = auth.get_validated_token(token)
        user = auth.get_user(validated)
        print(f"[WS_AUTH] SUCCESS: User token for {user.username}", file=sys.stderr, flush=True)
        return WsAuthResult(role="user", user=user)
    except Exception as e:
        print(f"[WS_AUTH] User token failed: {type(e).__name__}: {e}", file=sys.stderr, flush=True)

    # 2) Try device token signed by our SECRET_KEY
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=["HS256"])
        print(f"[WS_AUTH] Device token decoded: {payload}", file=sys.stderr, flush=True)
        if payload.get("role") != "device":
            print(f"[WS_AUTH] FAIL: Device token role mismatch: {payload.get('role')}", file=sys.stderr, flush=True)
            return None
        device_id = payload.get("device_id")
        if not isinstance(device_id, str) or not device_id:
            print(f"[WS_AUTH] FAIL: Device token missing device_id", file=sys.stderr, flush=True)
            return None
        print(f"[WS_AUTH] SUCCESS: Device token for {device_id}", file=sys.stderr, flush=True)
        return WsAuthResult(role="device", device_id=device_id)
    except jwt.ExpiredSignatureError:
        print(f"[WS_AUTH] FAIL: Device token EXPIRED", file=sys.stderr, flush=True)
        return None
    except Exception as e:
        print(f"[WS_AUTH] FAIL: Device token decode error: {type(e).__name__}: {e}", file=sys.stderr, flush=True)
        return None

