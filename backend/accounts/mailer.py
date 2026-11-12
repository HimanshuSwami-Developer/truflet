"""Sends the sign-in code by email.

Configure SMTP (Gmail, SES, SendGrid, Mailgun …) with the EMAIL_* settings in .env.
Without EMAIL_HOST the console backend prints the email to the server log.
"""
from django.conf import settings
from django.core.mail import EmailMultiAlternatives
from django.template.loader import render_to_string


def send_login_code(email, code):
    ctx = {"code": code, "minutes": 10, "app": "Turflet"}
    text = render_to_string("emails/login_code.txt", ctx)
    html = render_to_string("emails/login_code.html", ctx)
    msg = EmailMultiAlternatives(f"{code} is your Turflet sign-in code", text, settings.DEFAULT_FROM_EMAIL, [email])
    msg.attach_alternative(html, "text/html")
    msg.send(fail_silently=False)
