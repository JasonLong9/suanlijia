import secrets
from datetime import datetime, timedelta
from decimal import Decimal

import jwt
from django.conf import settings
from django.contrib.auth import authenticate
from django.contrib.auth.models import User
from django.db import transaction
from django.utils import timezone
from django.contrib.auth.hashers import check_password, make_password
from rest_framework.permissions import AllowAny, IsAdminUser, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework_simplejwt.tokens import RefreshToken

from .models import (
    Account,
    BillingRecord,
    EndReason,
    IdempotencyKey,
    Lease,
    LeaseStatus,
    Node,
    NodeStatus,
    PricePlan,
)
from .serializers import (
    BillingRecordSerializer,
    DeviceTokenRequestSerializer,
    LeaseSerializer,
    LoginRequestSerializer,
    NodeSerializer,
    PricePlanSerializer,
    RegisterRequestSerializer,
    ReleaseRequestSerializer,
    RentRequestSerializer,
    RequestNicknameSerializer,
    TokenLoginRequestSerializer,
    UpdateUserInfoSerializer,
)
from .services.ws import send_ws
from .services.lease_lifecycle import end_lease, push_lease_update, push_pool_update, serialize_lease


def _error(code: str, message: str, details=None, *, status_code: int = 400):
    payload = {"code": code, "message": message}
    if details is not None:
        payload["details"] = details
    return Response(payload, status=status_code)


def _ensure_account(user: User) -> Account:
    account, _ = Account.objects.get_or_create(user=user)
    return account


def _get_price(region: str, gpu_tier: str, billing_unit: str) -> Decimal:
    plan = (
        PricePlan.objects.filter(region=region, gpu_tier=gpu_tier, billing_unit=billing_unit)
        .order_by("id")
        .first()
    )
    if plan is None:
        return Decimal("0")
    return plan.unit_price


def _gen_lease_token() -> str:
    # 32 bytes -> 43 chars base64url, high entropy
    return secrets.token_urlsafe(32)


def _user_nickname(user: User) -> str:
    return user.first_name or user.username


def _issue_tokens(user: User):
    refresh = RefreshToken.for_user(user)
    return str(refresh.access_token), str(refresh)


class RegisterView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = RegisterRequestSerializer(data=request.data)
        if not serializer.is_valid():
            return _error("BAD_REQUEST", "invalid payload", serializer.errors)

        data = serializer.validated_data
        username = data["username"]
        if User.objects.filter(username=username).exists():
            return _error("USERNAME_TAKEN", "username already exists", status_code=400)

        user = User.objects.create_user(
            username=username,
            password=data["password"],
            email=data["email"],
            first_name=data["nickname"],
        )
        _ensure_account(user)
        return Response({"status": "success"}, status=201)


class LoginView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = LoginRequestSerializer(data=request.data)
        if not serializer.is_valid():
            return _error("BAD_REQUEST", "invalid payload", serializer.errors)

        user = authenticate(
            username=serializer.validated_data["username"],
            password=serializer.validated_data["password"],
        )
        if user is None:
            return _error("UNAUTHORIZED", "invalid credentials", status_code=401)

        access, refresh = _issue_tokens(user)
        return Response(
            {
                "access": access,
                "refresh": refresh,
                "uid": str(user.id),
                "nickname": _user_nickname(user),
                "chattoken": "disabled",
            }
        )


class TokenLoginView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = TokenLoginRequestSerializer(data=request.data)
        if not serializer.is_valid():
            return _error("BAD_REQUEST", "invalid payload", serializer.errors)

        token_str = serializer.validated_data["token"]
        auth = JWTAuthentication()
        try:
            validated = auth.get_validated_token(token_str)
            user = auth.get_user(validated)
        except Exception:
            return _error("UNAUTHORIZED", "invalid token", status_code=401)

        access, refresh = _issue_tokens(user)
        return Response(
            {
                "access": access,
                "refresh": refresh,
                "uid": str(user.id),
                "nickname": _user_nickname(user),
                "chattoken": "disabled",
            }
        )


class RequestNicknameView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = RequestNicknameSerializer(data=request.data)
        if not serializer.is_valid():
            return _error("BAD_REQUEST", "invalid payload", serializer.errors)

        uid = serializer.validated_data["uid"]
        try:
            user = User.objects.get(id=int(uid))
        except Exception:
            return _error("NOT_FOUND", "user not found", status_code=404)
        return Response({"nickname": _user_nickname(user)})


class UpdateUserInfoView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = UpdateUserInfoSerializer(data=request.data)
        if not serializer.is_valid():
            return _error("BAD_REQUEST", "invalid payload", serializer.errors)

        token_str = serializer.validated_data["token"]
        auth = JWTAuthentication()
        try:
            validated = auth.get_validated_token(token_str)
            user = auth.get_user(validated)
        except Exception:
            return _error("UNAUTHORIZED", "invalid token", status_code=401)

        user.first_name = serializer.validated_data["newname"]
        user.save(update_fields=["first_name"])
        return Response({"ok": True})


class GetLatestVersionView(APIView):
    permission_classes = [AllowAny]

    def get(self, request):
        return Response({"version": getattr(settings, "CPP_LATEST_VERSION", "unknown")})


class DeviceTokenView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        print(f"DEBUG: DeviceTokenView.post entered. Headers: {request.headers}")
        # Force reload
        serializer = DeviceTokenRequestSerializer(data=request.data)
        if not serializer.is_valid():
            print(f"DEBUG: Serializer invalid: {serializer.errors}")
            return _error("BAD_REQUEST", "invalid payload", serializer.errors)

        device_id = serializer.validated_data["device_id"]
        device_secret = serializer.validated_data["device_secret"]
        print(f"DEBUG: DeviceTokenView requested for device_id={device_id}")
        
        try:
            node = Node.objects.get(device_id=device_id)
            print(f"DEBUG: Found existing node {node.device_id}, updating secret")
            # Existing node: update secret to support diskless re-imaging
            node.device_secret_hash = make_password(device_secret)
            node.updated_at = timezone.now()
            node.save(update_fields=["device_secret_hash", "updated_at"])
            print("DEBUG: Node updated")
        except Node.DoesNotExist:
            print("DEBUG: Creating new node")
            # New node: auto-register
            node = Node.objects.create(
                device_id=device_id,
                device_secret_hash=make_password(device_secret),
                status=NodeStatus.OFFLINE,
                region="unknown",
                gpu_tier="unknown",
            )
            print("DEBUG: Node created")

        payload = {
            "role": "device",
            "device_id": device_id,
            "exp": datetime.utcnow() + timedelta(days=7),
        }
        try:
            token = jwt.encode(payload, settings.SECRET_KEY, algorithm="HS256")
            print("DEBUG: Token generated")
        except Exception as e:
            print(f"DEBUG: Token generation failed: {e}")
            raise

        response = Response({"device_token": token})
        print(f"DEBUG: Returning response 200: {response.data}")
        return response


class PoolNodesView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        region = request.query_params.get("region")
        gpu_tier = request.query_params.get("gpu_tier")
        status = request.query_params.get("status")

        nodes = Node.objects.all().order_by("device_id")
        if region:
            nodes = nodes.filter(region=region)
        if gpu_tier:
            nodes = nodes.filter(gpu_tier=gpu_tier)
        if status:
            nodes = nodes.filter(status=status)

        prices = PricePlan.objects.all().order_by("region", "gpu_tier", "billing_unit")
        if region:
            prices = prices.filter(region=region)
        if gpu_tier:
            prices = prices.filter(gpu_tier=gpu_tier)

        return Response(
            {
                "nodes": NodeSerializer(nodes, many=True).data,
                "prices": PricePlanSerializer(prices, many=True).data,
            }
        )


class RentLeaseView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = RentRequestSerializer(data=request.data)
        if not serializer.is_valid():
            return _error("BAD_REQUEST", "invalid payload", serializer.errors)

        user = request.user
        region = serializer.validated_data["region"]
        gpu_tier = serializer.validated_data["gpu_tier"]
        billing_unit = serializer.validated_data["billing_unit"]
        count = serializer.validated_data["count"]
        client_request_id = (serializer.validated_data.get("client_request_id") or "").strip()

        if client_request_id:
            existing = IdempotencyKey.objects.filter(
                user=user, scope="rent", key=client_request_id
            ).first()
            if existing is not None:
                return Response(existing.response_json)

        now = timezone.now()
        leases = []

        with transaction.atomic():
            query = Node.objects.select_for_update().filter(
                status=NodeStatus.FREE,
                gpu_tier=gpu_tier,
            )
            if region != "default":
                query = query.filter(region=region)
            
            free_nodes = list(query.order_by("last_seen")[:count])
            if len(free_nodes) < count:
                return _error(
                    "NO_CAPACITY",
                    "no capacity",
                    {"requested": count, "available": len(free_nodes)},
                    status_code=409,
                )

            unit_price = _get_price(region=region, gpu_tier=gpu_tier, billing_unit=billing_unit)

            for node in free_nodes:
                lease = Lease.objects.create(
                    user=user,
                    device=node,
                    status=LeaseStatus.ASSIGNED,
                    billing_unit=billing_unit,
                    unit_price=unit_price,
                    assigned_at=now,
                    lease_token=_gen_lease_token(),
                )
                node.status = NodeStatus.ASSIGNED
                node.save(update_fields=["status", "updated_at"])
                leases.append(lease)

        # notify nodes + user after commit
        lease_token_map = {}
        for lease in leases:
            lease_token_map[str(lease.lease_id)] = lease.lease_token
            send_ws(
                f"node_{lease.device_id}",
                "lease_assigned",
                {
                    "lease_id": str(lease.lease_id),
                    "device_id": lease.device_id,
                    "lease_token": lease.lease_token,
                    "billing_unit": lease.billing_unit,
                },
            )
            push_lease_update(lease)

        push_pool_update()

        response_json = {
            "leases": [serialize_lease(l) for l in leases],
            "lease_token_map": lease_token_map,
        }
        if client_request_id:
            IdempotencyKey.objects.create(
                user=user, scope="rent", key=client_request_id, response_json=response_json
            )
        return Response(response_json)


class ReleaseLeaseView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = ReleaseRequestSerializer(data=request.data)
        if not serializer.is_valid():
            return _error("BAD_REQUEST", "invalid payload", serializer.errors)

        user = request.user
        lease_ids = serializer.validated_data["lease_ids"]
        client_request_id = (serializer.validated_data.get("client_request_id") or "").strip()

        if client_request_id:
            existing = IdempotencyKey.objects.filter(
                user=user, scope="release", key=client_request_id
            ).first()
            if existing is not None:
                return Response(existing.response_json)

        ended_at = timezone.now()
        leases = []

        with transaction.atomic():
            for lease_id in lease_ids:
                try:
                    lease = Lease.objects.select_for_update().get(
                        lease_id=lease_id, user=user
                    )
                except Lease.DoesNotExist:
                    return _error("NOT_FOUND", "lease not found", {"lease_id": lease_id}, status_code=404)

                end_lease(
                    lease=lease,
                    end_reason=EndReason.USER_RELEASE,
                    ended_at=ended_at,
                )
                leases.append(lease)

                node = lease.device
                if node.status not in (NodeStatus.DISABLED, NodeStatus.MAINTENANCE):
                    node.status = NodeStatus.RELEASING
                    node.save(update_fields=["status", "updated_at"])

        for lease in leases:
            send_ws(
                f"node_{lease.device_id}",
                "lease_release",
                {
                    "lease_id": str(lease.lease_id),
                    "device_id": lease.device_id,
                    "reason": EndReason.USER_RELEASE,
                },
            )
            push_lease_update(lease)

        push_pool_update()

        response_json = {"leases": [serialize_lease(l) for l in leases]}
        if client_request_id:
            IdempotencyKey.objects.create(
                user=user, scope="release", key=client_request_id, response_json=response_json
            )
        return Response(response_json)


class BillingInfoView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        account = _ensure_account(request.user)
        active = Lease.objects.filter(
            user=request.user,
            status__in=[
                LeaseStatus.PENDING,
                LeaseStatus.ASSIGNED,
                LeaseStatus.READY,
                LeaseStatus.ACTIVE,
                LeaseStatus.RELEASING,
            ],
        ).order_by("-created_at")
        history = BillingRecord.objects.filter(user=request.user).order_by("-created_at")[:50]
        return Response(
            {
                "currency": account.currency,
                "balance": float(account.balance),
                "active_leases": LeaseSerializer(active, many=True).data,
                "history": BillingRecordSerializer(history, many=True).data,
            }
        )


class AdminNodesView(APIView):
    permission_classes = [IsAdminUser]

    def get(self, request):
        nodes = Node.objects.all().order_by("device_id")
        return Response({"nodes": NodeSerializer(nodes, many=True).data})


class AdminSetNodeStateView(APIView):
    permission_classes = [IsAdminUser]

    def post(self, request, device_id: str):
        state = (request.data or {}).get("state")
        if state not in ("DISABLED", "MAINTENANCE", "FREE"):
            return _error("BAD_REQUEST", "invalid state", {"state": state})

        try:
            node = Node.objects.get(device_id=device_id)
        except Node.DoesNotExist:
            return _error("NOT_FOUND", "node not found", status_code=404)

        if state == "FREE":
            # only set FREE if node is online; otherwise keep OFFLINE.
            node.status = NodeStatus.FREE if node.connection_id else NodeStatus.OFFLINE
        else:
            node.status = state
        node.save(update_fields=["status", "updated_at"])
        push_pool_update()
        return Response(NodeSerializer(node).data)


# ========== Download Views ==========
from django.http import HttpResponse, FileResponse
import os

class DownloadPageView(APIView):
    """Download page for all client versions."""
    permission_classes = [AllowAny]
    
    def get(self, request):
        html = """<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>算力橙客户端下载</title>
    <style>
        body { font-family: system-ui, sans-serif; max-width: 700px; margin: 50px auto; padding: 20px; }
        h1 { color: #1890ff; border-bottom: 2px solid #eee; padding-bottom: 10px; }
        h2 { color: #333; margin-top: 30px; }
        .download-item { background: #f9f9f9; border-radius: 8px; padding: 15px; margin: 15px 0; }
        .download-item:hover { background: #f0f0f0; }
        .btn { display: inline-block; background: #1890ff; color: white; padding: 12px 24px; 
               text-decoration: none; border-radius: 6px; font-size: 16px; }
        .btn:hover { background: #40a9ff; }
        .btn-primary { background: #52c41a; font-size: 18px; padding: 15px 30px; }
        .btn-primary:hover { background: #73d13d; }
        .desc { color: #666; font-size: 14px; margin-top: 8px; }
        .tag { display: inline-block; background: #ff4d4f; color: white; padding: 2px 8px; 
               border-radius: 4px; font-size: 12px; margin-left: 8px; }
        .tag-recommended { background: #1890ff; }
        .info { color: #666; font-size: 14px; background: #fff7e6; padding: 15px; border-radius: 8px; }
        ol { padding-left: 20px; }
        code { background: #f5f5f5; padding: 2px 6px; border-radius: 4px; }
        .primary-download { background: #e6f7ff; border: 2px solid #1890ff; }
    </style>
</head>
<body>
    <h1>算力橙 (SLC) 客户端下载</h1>
    
    <div class="download-item primary-download">
        <a href="/api/download/pool-node/" class="btn btn-primary">下载 算力池节点版 (v3.24 推荐)</a>
        <span class="tag tag-recommended">推荐</span>
        <div class="desc">修复黑屏/无界面问题，增强远程连接稳定性 (推荐)</div>
    </div>
    
    <div class="download-item">
        <a href="/api/download/official/" class="btn">下载 官方原版 GUI</a>
        <div class="desc">纯官方代码，点对点连接模式</div>
    </div>
    
    <div class="download-item">
        <a href="/api/download/v12.2/" class="btn">下载 Headless 版 (V12.2)</a>
        <div class="desc">无头模式定制版 - 适用于 Windows 服务运行</div>
    </div>
    
    <h2>安装说明</h2>
    <div class="info">
        <p><strong>算力池节点版（推荐）：</strong></p>
        <ol>
            <li>下载并解压 zip 文件</li>
            <li>双击运行 <code>slc.exe</code></li>
            <li>程序会自动登录并最小化到系统托盘</li>
            <li>设备将自动注册为算力池节点，可在管理后台查看</li>
            <li>等待来自算力池的远程连接请求</li>
        </ol>
    </div>
</body>
</html>"""
        return HttpResponse(html, content_type='text/html; charset=utf-8')


class DownloadV122View(APIView):
    """Direct file download for V12.2 client zip."""
    permission_classes = [AllowAny]
    
    def get(self, request):
        file_path = '/SuanLiJia/SLCNode-win64-v12.2-Release.zip'
        if not os.path.exists(file_path):
            return HttpResponse('File not found', status=404)
        
        response = FileResponse(
            open(file_path, 'rb'),
            content_type='application/zip'
        )
        response['Content-Disposition'] = 'attachment; filename="SLCNode-win64-v12.2-Release.zip"'
        return response


class DownloadGUIView(APIView):
    """Direct file download for GUI test version."""
    permission_classes = [AllowAny]
    
    def get(self, request):
        file_path = '/SuanLiJia/SLCNode-win64-GUI-Release.zip'
        if not os.path.exists(file_path):
            return HttpResponse('File not found', status=404)
        
        response = FileResponse(
            open(file_path, 'rb'),
            content_type='application/zip'
        )
        response['Content-Disposition'] = 'attachment; filename="SLCNode-win64-GUI-Release.zip"'
        return response


class DownloadOfficialView(APIView):
    """Direct file download for official GUI version."""
    permission_classes = [AllowAny]
    
    def get(self, request):
        file_path = '/SuanLiJia/CloudPlayPlus-GUI-Official.zip'
        if not os.path.exists(file_path):
            return HttpResponse('File not found', status=404)
        
        response = FileResponse(
            open(file_path, 'rb'),
            content_type='application/zip'
        )
        response['Content-Disposition'] = 'attachment; filename="CloudPlayPlus-GUI-Official.zip"'
        return response


class DownloadPoolNodeView(APIView):
    """Direct file download for pool node GUI version."""
    permission_classes = [AllowAny]
    
    def get(self, request):
        file_path = '/SuanLiJia/SLC-Pool-Node-GUI-v3.21.zip'
        if not os.path.exists(file_path):
            return HttpResponse('File not found', status=404)
        
        response = FileResponse(
            open('/SuanLiJia/SLC-Pool-Node-GUI-v3.24.zip', 'rb'),
            content_type='application/zip'
        )
        response['Content-Disposition'] = 'attachment; filename="SLC-Pool-Node-GUI-v3.24.zip"'
        return response


class AdminForceReleaseLeaseView(APIView):
    permission_classes = [IsAdminUser]

    def post(self, request, lease_id):
        try:
            lease = Lease.objects.select_related("device").get(lease_id=lease_id)
        except Lease.DoesNotExist:
            return _error("NOT_FOUND", "lease not found", status_code=404)

        with transaction.atomic():
            end_lease(
                lease=lease,
                end_reason=EndReason.ADMIN_FORCE_RELEASE,
                ended_at=timezone.now(),
            )
            node = lease.device
            if node.status not in (NodeStatus.DISABLED, NodeStatus.MAINTENANCE):
                node.status = NodeStatus.RELEASING
                node.save(update_fields=["status", "updated_at"])

        send_ws(
            f"node_{lease.device_id}",
            "lease_release",
            {
                "lease_id": str(lease.lease_id),
                "device_id": lease.device_id,
                "reason": EndReason.ADMIN_FORCE_RELEASE,
            },
        )
        push_lease_update(lease)
        push_pool_update()
        return Response(serialize_lease(lease))


class AdminForceReleaseNodeView(APIView):
    permission_classes = [IsAdminUser]

    def post(self, request, device_id: str):
        now = timezone.now()
        with transaction.atomic():
            node = Node.objects.select_for_update().filter(device_id=device_id).first()
            if node is None:
                return _error("NOT_FOUND", "node not found", status_code=404)

            leases = list(
                Lease.objects.select_for_update()
                .filter(
                    device=node,
                    status__in=[
                        LeaseStatus.PENDING,
                        LeaseStatus.ASSIGNED,
                        LeaseStatus.READY,
                        LeaseStatus.ACTIVE,
                        LeaseStatus.RELEASING,
                    ],
                )
                .order_by("-created_at")
            )

            for lease in leases:
                end_lease(
                    lease=lease,
                    end_reason=EndReason.ADMIN_FORCE_RELEASE,
                    ended_at=now,
                )

            # Always reset node status (not just when there are leases)
            if node.status not in (NodeStatus.DISABLED, NodeStatus.MAINTENANCE):
                # If node has connection, set to FREE; otherwise OFFLINE
                node.status = NodeStatus.FREE if node.connection_id else NodeStatus.OFFLINE
                node.save(update_fields=["status", "updated_at"])

        for lease in leases:
            send_ws(
                f"node_{lease.device_id}",
                "lease_release",
                {
                    "lease_id": str(lease.lease_id),
                    "device_id": lease.device_id,
                    "reason": EndReason.ADMIN_FORCE_RELEASE,
                },
            )
            push_lease_update(lease)

        push_pool_update()
        return Response({"device_id": device_id, "leases_ended": len(leases), "new_status": node.status})


class AdminRebootNodeView(APIView):
    permission_classes = [IsAdminUser]

    def post(self, request, device_id: str):
        try:
            Node.objects.get(device_id=device_id)
        except Node.DoesNotExist:
            return _error("NOT_FOUND", "node not found", status_code=404)

        # Node 端目前只实现了 lease_release 的重启回收逻辑，运维重启先按扩展消息预留。
        send_ws(f"node_{device_id}", "node_reboot", {"device_id": device_id})
        return Response({"accepted": True}, status=202)


class AdminDeleteNodeView(APIView):
    """删除节点（管理员）"""
    permission_classes = [IsAdminUser]

    def delete(self, request, device_id: str):
        try:
            node = Node.objects.get(device_id=device_id)
        except Node.DoesNotExist:
            return _error("NOT_FOUND", "node not found", status_code=404)

        # 检查是否有活动租约
        active_leases = Lease.objects.filter(
            device=node,
            status__in=[
                LeaseStatus.PENDING,
                LeaseStatus.ASSIGNED,
                LeaseStatus.READY,
                LeaseStatus.ACTIVE,
                LeaseStatus.RELEASING,
            ]
        ).count()

        if active_leases > 0:
            return _error(
                "HAS_ACTIVE_LEASES",
                f"Cannot delete node with {active_leases} active lease(s). Please release all leases first.",
                status_code=400
            )

        # 删除节点
        node.delete()
        push_pool_update()
        
        return Response({
            "success": True,
            "device_id": device_id,
            "message": "Node deleted successfully"
        })


class LeaseListView(APIView):
    """获取当前用户的所有活动租赁列表"""
    permission_classes = [IsAuthenticated]

    def get(self, request):
        active_statuses = [
            LeaseStatus.PENDING,
            LeaseStatus.ASSIGNED,
            LeaseStatus.READY,
            LeaseStatus.ACTIVE,
            LeaseStatus.RELEASING,
        ]
        leases = Lease.objects.filter(
            user=request.user,
            status__in=active_statuses,
        ).order_by("-created_at")
        return Response({"leases": [serialize_lease(l) for l in leases]})


class AdminUpdateNodeView(APIView):
    """管理员更新节点信息（昵称、地区、显卡型号）"""
    permission_classes = [IsAdminUser]

    def patch(self, request, device_id: str):
        try:
            node = Node.objects.get(device_id=device_id)
        except Node.DoesNotExist:
            return _error("NOT_FOUND", "node not found", status_code=404)

        data = request.data or {}
        updated_fields = ["updated_at"]

        if "nickname" in data:
            node.nickname = data["nickname"]
            updated_fields.append("nickname")
        if "region" in data:
            node.region = data["region"]
            updated_fields.append("region")
        if "gpu_tier" in data:
            node.gpu_tier = data["gpu_tier"]
            updated_fields.append("gpu_tier")

        if len(updated_fields) > 1:  # more than just updated_at
            node.save(update_fields=updated_fields)
            push_pool_update()

        return Response(NodeSerializer(node).data)


class ClientLogView(APIView):
    """接收客户端日志（用于调试）"""
    permission_classes = [AllowAny]  # 允许未认证的设备发送日志

    def post(self, request):
        data = request.data or {}
        device_id = data.get('device_id', 'unknown')
        level = data.get('level', 'INFO')
        message = data.get('message', '')
        timestamp = data.get('timestamp', '')
        context = data.get('context', {})

        # 写入日志文件
        log_line = f"[CLIENT_LOG] [{timestamp}] [{device_id}] [{level}] {message}"
        if context:
            log_line += f" | context: {context}"
        print(log_line)

        # 同时写入专门的客户端日志文件
        try:
            import os
            log_dir = '/SuanLiJia/backend/logs'
            os.makedirs(log_dir, exist_ok=True)
            with open(f'{log_dir}/client_{device_id}.log', 'a') as f:
                f.write(log_line + '\n')
        except Exception as e:
            print(f"[CLIENT_LOG] Failed to write log file: {e}")

        return Response({"received": True})
