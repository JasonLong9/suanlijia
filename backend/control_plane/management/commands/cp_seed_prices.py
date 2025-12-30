from decimal import Decimal

from django.core.management.base import BaseCommand

from control_plane.models import BillingUnit, PricePlan


class Command(BaseCommand):
    help = "Seed example price plans (idempotent upsert)."

    def handle(self, *args, **options):
        seeds = [
            ("cn-shanghai", "tier_7", BillingUnit.MINUTE, Decimal("0.5")),
            ("cn-shanghai", "tier_7", BillingUnit.HOUR, Decimal("20")),
            ("cn-shanghai", "tier_7", BillingUnit.DAY, Decimal("300")),
            ("cn-shanghai", "tier_7", BillingUnit.WEEK, Decimal("1800")),
            ("cn-shanghai", "tier_7", BillingUnit.MONTH, Decimal("6000")),
        ]

        for region, gpu_tier, unit, price in seeds:
            PricePlan.objects.update_or_create(
                region=region,
                gpu_tier=gpu_tier,
                billing_unit=unit,
                defaults={"unit_price": price},
            )

        self.stdout.write(self.style.SUCCESS("Seeded price plans."))

