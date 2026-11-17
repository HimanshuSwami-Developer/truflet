from django.contrib import admin

from .models import DeviceToken, Notification

admin.site.register([Notification, DeviceToken])
