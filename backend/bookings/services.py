"""Slot availability, pricing, holds, payment, cancellation and rescheduling."""
from datetime import timedelta
from decimal import ROUND_HALF_UP, Decimal

from django.db import transaction
from django.db.models import Q
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from core.models import AppConfig, RefundRule, notify
from venues.models import BlockedSlot, Court, VenueSport

from .models import Booking, Coupon, make_booking_code
from .payments import get_provider


def fmt_hour(h):
    return f"{(h % 12) or 12} {'AM' if h % 24 < 12 else 'PM'}"


def fmt_time(h):
    return f"{(h % 12) or 12}:00 {'AM' if h % 24 < 12 else 'PM'}"


def taken_hours(court, date, exclude_booking=None):
    now = timezone.now()
    qs = Booking.objects.filter(court=court, date=date).filter(
        Q(status="confirmed") | Q(status="held", held_until__gt=now)
    )
    if exclude_booking is not None:
        qs = qs.exclude(pk=exclude_booking.pk)
    taken = set()
    for b in qs.only("start_hour", "duration"):
        taken.update(range(b.start_hour, b.start_hour + b.duration))
    for blk in BlockedSlot.objects.filter(venue=court.venue, date=date).filter(Q(court=court) | Q(court__isnull=True)):
        taken.update(range(blk.start_hour, blk.end_hour))
    return taken


def slot_grid(venue_sport, court, date, exclude_booking=None):
    venue = venue_sport.venue
    today = timezone.localdate()
    now_hour = timezone.localtime().hour
    taken = taken_hours(court, date, exclude_booking)
    slots = []
    for h in range(venue.opens_at, venue.closes_at):
        past = date < today or (date == today and h <= now_hour)
        booked = (not past) and h in taken
        slots.append({
            "hour": h,
            "label": fmt_hour(h),
            "price": venue_sport.price_for(h),
            "peak": venue.is_peak(h),
            "status": "past" if past else "booked" if booked else "free",
        })
    return slots


def check_range(venue_sport, court, date, start, duration, exclude_booking=None):
    """Return an error string, or None when every hour is free."""
    venue = venue_sport.venue
    if duration < 1 or duration > 6:
        return "Pick a duration between 1 and 6 hours."
    grid = {s["hour"]: s for s in slot_grid(venue_sport, court, date, exclude_booking)}
    for h in range(start, start + duration):
        if h >= venue.closes_at:
            return f"Venue closes at {fmt_hour(venue.closes_at)}. Pick an earlier start or a shorter duration."
        slot = grid.get(h)
        if slot is None or slot["status"] != "free":
            return f"The {fmt_hour(h)} slot is not available. Pick another start time or duration."
    return None


def price_breakdown(venue_sport, start, duration, coupon=None, user=None):
    cfg = AppConfig.get()
    hours = list(range(start, start + duration))
    slot_amount = sum(venue_sport.price_for(h) for h in hours)
    peak_hours = sum(1 for h in hours if venue_sport.venue.is_peak(h))
    fee = cfg.convenience_fee
    gst = int((Decimal(fee) * cfg.gst_percent / 100).quantize(Decimal("1"), rounding=ROUND_HALF_UP))
    discount = 0
    if coupon:
        err = coupon.validate(user, slot_amount)
        if err:
            raise ValidationError({"coupon": err})
        discount = coupon.discount_for(slot_amount)
    return {
        "slot_amount": slot_amount,
        "peak_hours": peak_hours,
        "rate": slot_amount // duration if duration else 0,
        "convenience_fee": fee,
        "gst": gst,
        "discount": discount,
        "total": slot_amount + fee + gst - discount,
    }


def resolve(venue, court_id, sport_id):
    try:
        vs = VenueSport.objects.select_related("venue", "sport").get(venue=venue, sport_id=sport_id)
    except VenueSport.DoesNotExist:
        raise ValidationError({"sport": "This sport is not offered at this venue."})
    try:
        court = Court.objects.get(pk=court_id, venue=venue, is_active=True, sports=vs.sport)
    except Court.DoesNotExist:
        raise ValidationError({"court": "Pick a court that supports this sport."})
    return vs, court


@transaction.atomic
def create_hold(user, venue, court_id, sport_id, date, start, duration):
    vs, court = resolve(venue, court_id, sport_id)
    Court.objects.select_for_update().filter(pk=court.pk).first()  # serialise holds per court
    err = check_range(vs, court, date, start, duration)
    if err:
        raise ValidationError({"slot": err})
    # one open hold per user: release older ones
    Booking.objects.filter(user=user, status="held").update(status="expired")
    p = price_breakdown(vs, start, duration)
    cfg = AppConfig.get()
    return Booking.objects.create(
        user=user, venue=venue, court=court, sport=vs.sport, date=date, start_hour=start, duration=duration,
        players=vs.max_players, held_until=timezone.now() + timedelta(minutes=cfg.hold_minutes),
        slot_amount=p["slot_amount"], peak_hours=p["peak_hours"], convenience_fee=p["convenience_fee"],
        gst=p["gst"], total=p["total"],
    )


def _vs(booking):
    return VenueSport.objects.select_related("venue").get(venue=booking.venue, sport=booking.sport)


def apply_coupon(booking, code):
    if booking.status != "held":
        raise ValidationError({"coupon": "Coupons can only be applied before paying."})
    vs = _vs(booking)
    if not code:
        booking.coupon = None
        p = price_breakdown(vs, booking.start_hour, booking.duration)
    else:
        coupon = Coupon.objects.filter(code=code.strip().upper()).first()
        if not coupon:
            raise ValidationError({"coupon": "That code is not valid."})
        p = price_breakdown(vs, booking.start_hour, booking.duration, coupon, booking.user)
        booking.coupon = coupon
    booking.discount = p["discount"]
    booking.total = p["total"]
    booking.save(update_fields=["coupon", "discount", "total", "updated_at"])
    return booking


@transaction.atomic
def pay(booking, method, upi_id=""):
    booking = Booking.objects.select_for_update().get(pk=booking.pk)
    if booking.status == "confirmed":
        return booking
    if booking.status != "held" or not booking.held_until or booking.held_until < timezone.now():
        booking.status = "expired"
        booking.save(update_fields=["status"])
        raise ValidationError({"booking": "Your slot hold expired. Please pick the slot again."})
    if method not in dict(Booking.METHODS):
        raise ValidationError({"method": "Unknown payment method."})
    if method == "wallet" and booking.user.wallet_balance < booking.total:
        raise ValidationError({"method": "Not enough Turflet balance."})
    result = get_provider().charge(booking, method, upi_id)
    if not result.success:
        booking.payment_status = "failed"
        booking.save(update_fields=["payment_status"])
        raise ValidationError({"payment": result.message or "Payment failed. Please try again."})
    if method == "wallet":
        booking.user.wallet_balance -= booking.total
        booking.user.save(update_fields=["wallet_balance"])
    booking.status = "confirmed"
    booking.payment_status = "paid"
    booking.payment_method = method
    booking.upi_id = upi_id
    booking.transaction_id = result.transaction_id
    booking.paid_at = timezone.now()
    booking.save()
    notify(booking.user, "Booking confirmed",
           f"{booking.venue.name} · {booking.date:%a, %-d %b} · {fmt_hour(booking.start_hour)}", "booking")
    from community.services import on_paid
    on_paid(booking)
    return booking


def cancel_quote(booking):
    hours_left = booking.hours_left
    pct = RefundRule.percent_for(hours_left)
    refundable_base = max(0, booking.slot_amount - booking.discount)
    refund = refundable_base * pct // 100
    return {
        "hours_left": round(hours_left, 1),
        "percent": pct,
        "amount_paid": booking.total,
        "charge": booking.total - refund,
        "refund": refund,
    }


@transaction.atomic
def cancel(booking, reason="", by_venue=False):
    if booking.status not in ("confirmed", "held"):
        raise ValidationError({"booking": "This booking can no longer be cancelled."})
    if booking.status == "held":
        booking.status = "expired"
        booking.save(update_fields=["status"])
        return booking
    if by_venue:
        refund = booking.total
    else:
        refund = cancel_quote(booking)["refund"]
    booking.status = "cancelled"
    booking.cancelled_at = timezone.now()
    booking.cancellation_code = make_booking_code("CXL")
    booking.cancel_reason = reason
    booking.refund_amount = refund
    if refund > 0:
        get_provider().refund(booking, refund)
        booking.payment_status = "refunded"
        booking.refunded_at = timezone.now()
    booking.save()
    notify(booking.user, "Booking cancelled",
           f"{booking.code} · refund ₹{refund}" if refund else f"{booking.code} cancelled", "booking")
    from community.services import on_cancelled
    on_cancelled(booking)
    return booking


@transaction.atomic
def reschedule(booking, date, start, court_id=None):
    cfg = AppConfig.get()
    if booking.status != "confirmed":
        raise ValidationError({"booking": "Only confirmed bookings can be rescheduled."})
    if booking.reschedule_count >= cfg.max_reschedules:
        raise ValidationError({"booking": "You have already used your free reschedule."})
    if booking.hours_left < cfg.reschedule_cutoff_hours:
        raise ValidationError({"booking": f"Reschedule is allowed up to {cfg.reschedule_cutoff_hours} hours before."})
    vs = _vs(booking)
    court = booking.court
    if court_id:
        court = Court.objects.get(pk=court_id, venue=booking.venue)
    err = check_range(vs, court, date, start, booking.duration, exclude_booking=booking)
    if err:
        raise ValidationError({"slot": err})
    booking.date, booking.start_hour, booking.court = date, start, court
    booking.reschedule_count += 1
    booking.save()
    return booking
