import datetime

from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.validators import validate_email
from django.shortcuts import redirect, render
from django.views.decorators.cache import cache_page

from accounts.mailer import send_login_code
from accounts.models import AccountDeletionRequest, EmailOTP, User, normalize_email

from .models import AppConfig

PRIVACY_UPDATED = datetime.date(2026, 11, 13)
DELETE_SESSION_KEY = "delete_account_email"


def _support():
    c = AppConfig.get()
    phone = c.support_phone if c.support_phone and c.support_phone != "+918000000000" else ""  # skip the placeholder
    return c.support_email, phone


@cache_page(60 * 15)
def privacy_policy(request):
    """Public privacy policy (linked from the Play Store listing and the app)."""
    email, phone = _support()
    return render(request, "legal/privacy.html", {"updated": PRIVACY_UPDATED, "email": email, "phone": phone})


def delete_account(request):
    """Public account-deletion request page (the Play Store "Delete account URL").

    Step 1: the person enters the email they sign in with and we email them a one-time code.
    Step 2: they enter the code (proving they own the account) and we record a deletion request
    for the team to process from the admin.
    """
    support_email, _ = _support()
    ctx = {"support_email": support_email, "step": "email", "error": "", "email": ""}

    if request.method == "POST":
        action = request.POST.get("action")

        if action == "send":
            email = normalize_email(request.POST.get("email"))
            ctx["email"] = email
            try:
                validate_email(email)
            except ValidationError:
                ctx["error"] = "Enter a valid email address."
                return render(request, "legal/delete_account.html", ctx)
            if not User.objects.filter(email=email).exists():
                ctx["error"] = "We couldn't find a Turflet account with this email."
                return render(request, "legal/delete_account.html", ctx)
            if EmailOTP.recently_sent(email):
                ctx["error"] = "A code was just sent. Please wait 30 seconds before asking again."
                return render(request, "legal/delete_account.html", ctx)
            code = EmailOTP.issue(email, dev_mode=settings.OTP_DEV_MODE)
            try:
                send_login_code(email, code)
            except Exception:
                if not settings.OTP_DEV_MODE:
                    ctx["error"] = "We couldn't send the email right now. Please try again."
                    return render(request, "legal/delete_account.html", ctx)
            request.session[DELETE_SESSION_KEY] = email
            ctx.update(step="code", email=email)
            return render(request, "legal/delete_account.html", ctx)

        if action == "confirm":
            email = request.session.get(DELETE_SESSION_KEY)
            if not email:
                return redirect("delete_account")
            ctx.update(step="code", email=email, reason=request.POST.get("reason", "")[:1000])
            code = request.POST.get("code", "").strip()
            otp = EmailOTP.objects.filter(email=email, used=False).first()
            if not otp or otp.is_expired():
                ctx["error"] = "Code expired. Start again to get a new one."
            elif otp.attempts >= EmailOTP.MAX_ATTEMPTS:
                ctx["error"] = "Too many attempts. Start again to get a new code."
            elif EmailOTP.hash(code) != otp.code_hash:
                otp.attempts += 1
                otp.save(update_fields=["attempts"])
                ctx["error"] = "That code is incorrect."
            if ctx["error"]:
                return render(request, "legal/delete_account.html", ctx)
            otp.used = True
            otp.save(update_fields=["used"])
            user = User.objects.filter(email=email).first()
            if not AccountDeletionRequest.objects.filter(email=email, status="pending").exists():
                AccountDeletionRequest.objects.create(email=email, user=user, reason=ctx["reason"])
            request.session.pop(DELETE_SESSION_KEY, None)
            ctx["step"] = "done"
            return render(request, "legal/delete_account.html", ctx)

    request.session.pop(DELETE_SESSION_KEY, None)
    return render(request, "legal/delete_account.html", ctx)
