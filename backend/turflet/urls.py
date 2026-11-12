from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.shortcuts import redirect
from django.urls import include, path
from rest_framework_simplejwt.views import TokenRefreshView

from accounts import api as accounts
from bookings import api as bookings
from community import api as community
from core import api as core
from venues import api as venues

api = [
    # auth & profile
    path("auth/otp/request/", accounts.otp_request),
    path("auth/otp/verify/", accounts.otp_verify),
    path("auth/refresh/", TokenRefreshView.as_view()),
    path("me/", accounts.me),
    path("me/sports/", accounts.my_sports),
    # content
    path("config/", core.app_config),
    path("faqs/", core.faqs),
    path("policies/", core.policies),
    path("notifications/", core.notifications),
    path("notifications/read/", core.notifications_read),
    path("support/tickets/", core.tickets),
    # venues
    path("cities/", venues.cities),
    path("locate/", venues.locate),
    path("sports/", venues.sports),
    path("venues/", venues.venue_list),
    path("venues/saved/", venues.saved),
    path("venues/<int:pk>/", venues.venue_detail),
    path("venues/<int:pk>/availability/", venues.availability),
    path("venues/<int:pk>/save/", venues.toggle_save),
    path("venues/<int:pk>/review/", venues.review),
    # bookings
    path("coupons/validate/", bookings.validate_coupon),
    path("bookings/", bookings.bookings),
    path("bookings/<int:pk>/", bookings.booking_detail),
    path("bookings/<int:pk>/coupon/", bookings.apply_coupon),
    path("bookings/<int:pk>/pay/", bookings.pay),
    path("bookings/<int:pk>/cancel/", bookings.cancel),
    path("bookings/<int:pk>/reschedule/", bookings.reschedule),
    # groups & open games
    path("groups/", community.groups),
    path("groups/join/", community.group_join),
    path("groups/<int:pk>/", community.group_detail),
    path("groups/<int:pk>/members/", community.group_add_member),
    path("groups/<int:pk>/members/<int:user_id>/remove/", community.group_remove_member),
    path("groups/<int:pk>/leave/", community.group_leave),
    path("venues/<int:pk>/open-games/", community.venue_open_games),
    path("open-games/<int:pk>/join/", community.open_game_join),
    path("open-games/<int:pk>/leave/", community.open_game_leave),
]

urlpatterns = [
    path("", lambda r: redirect("dashboard:home")),
    path("api/v1/", include(api)),
    path("admin-panel/", include("dashboard.urls")),
    path("django-admin/", admin.site.urls),
] + static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
