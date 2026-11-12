from django.contrib import admin

from .models import FAQ, AppConfig, Notification, PolicySection, RefundRule, SupportTicket

admin.site.register([AppConfig, FAQ, RefundRule, PolicySection, SupportTicket, Notification])
admin.site.site_header = "Turflet (raw database admin)"
