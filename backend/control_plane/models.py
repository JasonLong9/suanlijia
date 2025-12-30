import uuid

from django.contrib.auth.models import User
from django.db import models
from django.utils import timezone


class NodeStatus(models.TextChoices):
    OFFLINE = "OFFLINE"
    FREE = "FREE"
    ASSIGNED = "ASSIGNED"
    IN_USE = "IN_USE"
    RELEASING = "RELEASING"
    DISABLED = "DISABLED"
    MAINTENANCE = "MAINTENANCE"


class LeaseStatus(models.TextChoices):
    PENDING = "PENDING"
    ASSIGNED = "ASSIGNED"
    READY = "READY"
    ACTIVE = "ACTIVE"
    RELEASING = "RELEASING"
    ENDED = "ENDED"


class BillingUnit(models.TextChoices):
    MINUTE = "minute"
    HOUR = "hour"
    DAY = "day"
    WEEK = "week"
    MONTH = "month"


class EndReason(models.TextChoices):
    USER_RELEASE = "USER_RELEASE"
    NODE_OFFLINE = "NODE_OFFLINE"
    ADMIN_FORCE_RELEASE = "ADMIN_FORCE_RELEASE"
    TIMEOUT = "TIMEOUT"
    ERROR = "ERROR"


class Node(models.Model):
    device_id = models.CharField(primary_key=True, max_length=64)
    device_secret_hash = models.CharField(max_length=128, blank=True)

    nickname = models.CharField(max_length=128, null=True, blank=True)
    region = models.CharField(max_length=64, blank=True)
    gpu_tier = models.CharField(max_length=64, blank=True)
    status = models.CharField(
        max_length=16, choices=NodeStatus.choices, default=NodeStatus.OFFLINE
    )

    connection_id = models.CharField(max_length=64, null=True, blank=True)
    last_seen = models.DateTimeField(default=timezone.now)
    agent_version = models.CharField(max_length=32, null=True, blank=True)
    capabilities = models.JSONField(null=True, blank=True)

    updated_at = models.DateTimeField(auto_now=True)

    def mark_seen(self) -> None:
        self.last_seen = timezone.now()

    def __str__(self) -> str:
        return f"{self.device_id} ({self.region}/{self.gpu_tier}) {self.status}"


class PricePlan(models.Model):
    region = models.CharField(max_length=64)
    gpu_tier = models.CharField(max_length=64)
    billing_unit = models.CharField(max_length=16, choices=BillingUnit.choices)
    unit_price = models.DecimalField(max_digits=12, decimal_places=4)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["region", "gpu_tier", "billing_unit"],
                name="uniq_price_plan",
            )
        ]

    def __str__(self) -> str:
        return f"{self.region}/{self.gpu_tier}/{self.billing_unit}={self.unit_price}"


class Lease(models.Model):
    lease_id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    user = models.ForeignKey(User, on_delete=models.CASCADE)
    device = models.ForeignKey(Node, on_delete=models.PROTECT)

    status = models.CharField(
        max_length=16, choices=LeaseStatus.choices, default=LeaseStatus.PENDING
    )
    billing_unit = models.CharField(max_length=16, choices=BillingUnit.choices)

    unit_price = models.DecimalField(
        max_digits=12, decimal_places=4, null=True, blank=True
    )
    billed_units = models.PositiveIntegerField(null=True, blank=True)
    amount = models.DecimalField(max_digits=12, decimal_places=4, null=True, blank=True)

    assigned_at = models.DateTimeField(null=True, blank=True)
    started_at = models.DateTimeField(null=True, blank=True)
    ended_at = models.DateTimeField(null=True, blank=True)
    end_reason = models.CharField(
        max_length=32, choices=EndReason.choices, null=True, blank=True
    )

    lease_token = models.CharField(max_length=128, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self) -> str:
        return f"{self.lease_id} {self.device_id} {self.status}"

    @property
    def device_id(self) -> str:
        return self.device.device_id


class BillingRecord(models.Model):
    record_id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    lease = models.ForeignKey(Lease, on_delete=models.CASCADE)

    amount = models.DecimalField(max_digits=12, decimal_places=4)
    billed_units = models.PositiveIntegerField()
    billing_unit = models.CharField(max_length=16, choices=BillingUnit.choices)
    created_at = models.DateTimeField(auto_now_add=True)
    end_reason = models.CharField(
        max_length=32, choices=EndReason.choices, null=True, blank=True
    )


class Account(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE)
    currency = models.CharField(max_length=8, default="CNY")
    balance = models.DecimalField(max_digits=12, decimal_places=4, default=0)


class IdempotencyKey(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    scope = models.CharField(max_length=32)
    key = models.CharField(max_length=128)
    response_json = models.JSONField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["user", "scope", "key"],
                name="uniq_idempotency_key",
            )
        ]

