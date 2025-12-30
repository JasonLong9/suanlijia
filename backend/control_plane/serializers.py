from decimal import Decimal

from django.contrib.auth.models import User
from rest_framework import serializers

from .models import BillingRecord, Lease, Node, PricePlan


class NodeSerializer(serializers.ModelSerializer):
    class Meta:
        model = Node
        fields = [
            "device_id",
            "connection_id",
            "nickname",
            "region",
            "gpu_tier",
            "status",
            "last_seen",
            "agent_version",
        ]


class PricePlanSerializer(serializers.ModelSerializer):
    unit_price = serializers.SerializerMethodField()

    class Meta:
        model = PricePlan
        fields = ["region", "gpu_tier", "billing_unit", "unit_price"]

    def get_unit_price(self, obj: PricePlan) -> float:
        return float(obj.unit_price)


class LeaseSerializer(serializers.ModelSerializer):
    lease_id = serializers.SerializerMethodField()
    device_id = serializers.CharField(source="device.device_id", read_only=True)
    unit_price = serializers.SerializerMethodField()
    amount = serializers.SerializerMethodField()
    lease_token = serializers.CharField(required=False, allow_blank=True)

    class Meta:
        model = Lease
        fields = [
            "lease_id",
            "device_id",
            "status",
            "billing_unit",
            "unit_price",
            "billed_units",
            "amount",
            "started_at",
            "ended_at",
            "end_reason",
            "lease_token",
        ]

    def get_lease_id(self, obj: Lease) -> str:
        return str(obj.lease_id)

    def get_unit_price(self, obj: Lease):
        if obj.unit_price is None:
            return None
        return float(obj.unit_price)

    def get_amount(self, obj: Lease):
        if obj.amount is None:
            return None
        return float(obj.amount)


class BillingRecordSerializer(serializers.ModelSerializer):
    record_id = serializers.SerializerMethodField()
    lease_id = serializers.SerializerMethodField()
    amount = serializers.SerializerMethodField()

    class Meta:
        model = BillingRecord
        fields = [
            "record_id",
            "lease_id",
            "amount",
            "billed_units",
            "billing_unit",
            "created_at",
            "end_reason",
        ]

    def get_record_id(self, obj: BillingRecord) -> str:
        return str(obj.record_id)

    def get_lease_id(self, obj: BillingRecord) -> str:
        return str(obj.lease.lease_id)

    def get_amount(self, obj: BillingRecord) -> float:
        return float(obj.amount)


class RentRequestSerializer(serializers.Serializer):
    region = serializers.CharField()
    gpu_tier = serializers.CharField()
    billing_unit = serializers.ChoiceField(
        choices=["minute", "hour", "day", "week", "month"]
    )
    count = serializers.IntegerField(min_value=1, max_value=100)
    client_request_id = serializers.CharField(required=False, allow_blank=True)


class ReleaseRequestSerializer(serializers.Serializer):
    lease_ids = serializers.ListField(
        child=serializers.CharField(), allow_empty=False
    )
    client_request_id = serializers.CharField(required=False, allow_blank=True)


class DeviceTokenRequestSerializer(serializers.Serializer):
    device_id = serializers.CharField()
    device_secret = serializers.CharField()


class LoginRequestSerializer(serializers.Serializer):
    username = serializers.CharField()
    password = serializers.CharField()


class TokenLoginRequestSerializer(serializers.Serializer):
    token = serializers.CharField()


class RegisterRequestSerializer(serializers.Serializer):
    username = serializers.CharField()
    password = serializers.CharField()
    email = serializers.EmailField()
    nickname = serializers.CharField()


class RequestNicknameSerializer(serializers.Serializer):
    uid = serializers.CharField()


class UpdateUserInfoSerializer(serializers.Serializer):
    token = serializers.CharField()
    newname = serializers.CharField()

