from dataclasses import dataclass
from decimal import Decimal
from datetime import timedelta

from django.utils import timezone

from control_plane.models import BillingUnit


@dataclass(frozen=True)
class BillingResult:
    billed_units: int
    amount: Decimal


_UNIT_SECONDS = {
    BillingUnit.MINUTE: 60,
    BillingUnit.HOUR: 3600,
    BillingUnit.DAY: 86400,
    BillingUnit.WEEK: 604800,
}


def _ceil_div(numerator: int, denominator: int) -> int:
    return (numerator + denominator - 1) // denominator


def compute_billing(
    *,
    started_at,
    ended_at,
    billing_unit: str,
    unit_price: Decimal,
    tz=None,
) -> BillingResult:
    if started_at is None or ended_at is None:
        return BillingResult(billed_units=0, amount=Decimal("0"))

    if timezone.is_naive(started_at) or timezone.is_naive(ended_at):
        raise ValueError("started_at/ended_at must be timezone-aware")

    if ended_at < started_at:
        return BillingResult(billed_units=0, amount=Decimal("0"))

    unit = BillingUnit(billing_unit)

    if unit in _UNIT_SECONDS:
        duration_seconds = int((ended_at - started_at).total_seconds())
        billed_units = max(1, _ceil_div(max(duration_seconds, 0), _UNIT_SECONDS[unit]))
        return BillingResult(
            billed_units=billed_units,
            amount=(unit_price * Decimal(billed_units)),
        )

    if unit == BillingUnit.MONTH:
        # 自然月计费：按日历月边界取整，半开区间 [started_at, ended_at)
        # billed_months = months_between(YearMonth(start), YearMonth(end - ε)) + 1
        epsilon_end = ended_at - timedelta(microseconds=1)
        local_start = timezone.localtime(started_at, timezone=tz)
        local_end = timezone.localtime(epsilon_end, timezone=tz)

        start_index = local_start.year * 12 + local_start.month
        end_index = local_end.year * 12 + local_end.month
        billed_units = max(1, end_index - start_index + 1)
        return BillingResult(
            billed_units=billed_units,
            amount=(unit_price * Decimal(billed_units)),
        )

    raise ValueError(f"Unsupported billing_unit: {billing_unit}")
