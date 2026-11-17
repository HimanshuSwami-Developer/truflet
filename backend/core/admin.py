from django.contrib import admin

from .models import FAQ, AppConfig, PolicySection, RefundRule, SupportTicket

admin.site.register([AppConfig, FAQ, RefundRule, PolicySection, SupportTicket])
admin.site.site_header = "Turflet (raw database admin)"
