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
from core import views as core_pages
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
    path("devices/", core.devices),
    path("devices/remove/", core.devices_remove),
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
    # matches (lobbies)
    path("amenities/", venues.amenities),
    path("lobbies/", community.lobbies),
    path("lobbies/mine/", community.my_lobbies),
    path("lobbies/players/", community.players_lookup),
    path("lobbies/<int:pk>/", community.lobby_view),
    path("lobbies/<int:pk>/request/", community.lobby_request),
    path("lobbies/<int:pk>/messages/", community.lobby_messages),
    path("lobbies/<int:pk>/pay/", community.lobby_pay),
    path("lobbies/<int:pk>/requests/", community.lobby_requests),
    path("lobbies/<int:pk>/requests/<int:rid>/", community.request_detail),
    path("lobbies/<int:pk>/requests/<int:rid>/messages/", community.request_messages),
    path("lobbies/<int:pk>/requests/<int:rid>/<str:action>/", community.request_decide),
    path("lobbies/<int:pk>/members/<int:member_id>/remove/", community.lobby_remove_member),
    path("lobbies/<int:pk>/<str:action>/", community.lobby_action),
    path("venues/<int:pk>/lobbies/", community.venue_lobbies),
]

urlpatterns = [
    path("", lambda r: redirect("dashboard:home")),
    path("api/v1/", include(api)),
    path("privacy/", core_pages.privacy_policy, name="privacy"),
    path("privacy-policy/", core_pages.privacy_policy),
    path("admin-panel/", include("dashboard.urls")),
    path("django-admin/", admin.site.urls),
] + static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
