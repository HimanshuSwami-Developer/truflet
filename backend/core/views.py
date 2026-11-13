import datetime

from django.shortcuts import render
from django.views.decorators.cache import cache_page

from .models import AppConfig

PRIVACY_UPDATED = datetime.date(2026, 11, 13)


@cache_page(60 * 15)
def privacy_policy(request):
    """Public privacy policy (linked from the Play Store listing and the app)."""
    c = AppConfig.get()
    phone = c.support_phone if c.support_phone and c.support_phone != "+918000000000" else ""  # skip the placeholder
    return render(request, "legal/privacy.html", {
        "updated": PRIVACY_UPDATED, "email": c.support_email, "phone": phone,
    })
