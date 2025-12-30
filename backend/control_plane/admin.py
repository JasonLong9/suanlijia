from django.contrib import admin

from .models import Account, BillingRecord, IdempotencyKey, Lease, Node, PricePlan


@admin.register(Node)
class NodeAdmin(admin.ModelAdmin):
    list_display = (
        "device_id",
        "region",
        "gpu_tier",
        "status",
        "connection_id",
        "last_seen",
        "agent_version",
        "updated_at",
    )
    search_fields = ("device_id", "region", "gpu_tier")
    list_filter = ("status", "region", "gpu_tier")


@admin.register(Lease)
class LeaseAdmin(admin.ModelAdmin):
    list_display = (
        "lease_id",
        "user",
        "device",
        "status",
        "billing_unit",
        "unit_price",
        "billed_units",
        "amount",
        "started_at",
        "ended_at",
        "end_reason",
        "created_at",
    )
    search_fields = ("lease_id", "device__device_id", "user__username")
    list_filter = ("status", "billing_unit", "end_reason", "device__region")


@admin.register(PricePlan)
class PricePlanAdmin(admin.ModelAdmin):
    list_display = ("region", "gpu_tier", "billing_unit", "unit_price")
    search_fields = ("region", "gpu_tier")
    list_filter = ("billing_unit", "region", "gpu_tier")


@admin.register(BillingRecord)
class BillingRecordAdmin(admin.ModelAdmin):
    list_display = (
        "record_id",
        "user",
        "lease",
        "amount",
        "billed_units",
        "billing_unit",
        "created_at",
        "end_reason",
    )
    search_fields = ("record_id", "lease__lease_id", "user__username")
    list_filter = ("billing_unit", "end_reason")


@admin.register(Account)
class AccountAdmin(admin.ModelAdmin):
    list_display = ("user", "currency", "balance")
    search_fields = ("user__username",)


@admin.register(IdempotencyKey)
class IdempotencyKeyAdmin(admin.ModelAdmin):
    list_display = ("user", "scope", "key", "created_at")
    search_fields = ("user__username", "scope", "key")

