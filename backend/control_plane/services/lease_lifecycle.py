from decimal import Decimal
from typing import Dict

from django.db import transaction
from django.utils import timezone

from control_plane.models import BillingRecord, EndReason, Lease, LeaseStatus, Node, NodeStatus
from control_plane.serializers import LeaseSerializer, NodeSerializer
from control_plane.services.billing import compute_billing
from control_plane.services.ws import send_ws


def serialize_lease(lease: Lease) -> Dict:
    return LeaseSerializer(lease).data


def push_lease_update(lease: Lease) -> None:
    send_ws(
        f"user_{lease.user_id}",
        "lease_update",
        {"lease": serialize_lease(lease)},
    )


def push_pool_update() -> None:
    nodes = Node.objects.all().order_by("device_id")
    send_ws(
        "users",
        "pool_update",
        {"mode": "full", "nodes": NodeSerializer(nodes, many=True).data},
    )


def end_lease(*, lease: Lease, end_reason: str, ended_at) -> Lease:
    if lease.ended_at is not None:
        return lease

    lease.ended_at = ended_at
    lease.end_reason = end_reason
    lease.status = LeaseStatus.ENDED

    unit_price = lease.unit_price or Decimal("0")
    if lease.started_at is None:
        lease.billed_units = 0
        lease.amount = Decimal("0")
    else:
        result = compute_billing(
            started_at=lease.started_at,
            ended_at=ended_at,
            billing_unit=lease.billing_unit,
            unit_price=unit_price,
            tz=timezone.get_current_timezone(),
        )
        lease.billed_units = result.billed_units
        lease.amount = result.amount

    lease.save(
        update_fields=[
            "status",
            "ended_at",
            "end_reason",
            "billed_units",
            "amount",
            "updated_at",
        ]
    )

    BillingRecord.objects.create(
        user=lease.user,
        lease=lease,
        amount=lease.amount or Decimal("0"),
        billed_units=lease.billed_units or 0,
        billing_unit=lease.billing_unit,
        end_reason=end_reason,
    )
    return lease


def mark_node_offline_and_end_leases(*, device_id: str, reason: str = EndReason.NODE_OFFLINE) -> None:
    now = timezone.now()
    with transaction.atomic():
        node = Node.objects.select_for_update().filter(device_id=device_id).first()
        if node is None:
            return
        node.connection_id = None
        node.status = NodeStatus.OFFLINE
        node.last_seen = now
        node.save(update_fields=["connection_id", "status", "last_seen", "updated_at"])

        active_leases = list(
            Lease.objects.select_for_update()
            .filter(
                device=node,
                status__in=[
                    LeaseStatus.ASSIGNED,
                    LeaseStatus.READY,
                    LeaseStatus.ACTIVE,
                    LeaseStatus.RELEASING,
                ],
            )
            .order_by("-created_at")
        )
        for lease in active_leases:
            end_lease(lease=lease, end_reason=reason, ended_at=now)

    for lease in active_leases:
        push_lease_update(lease)
    push_pool_update()
