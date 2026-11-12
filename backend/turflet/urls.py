from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.shortcuts import redirect
from django.urls import include, path
from rest_framework_simplejwt.views import TokenRefreshView

from accounts import api as accounts
from bookings import api as bookings
from core import api as core
from play import api as play
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
    # squad
    path("squad/groups/", play.groups),
    path("squad/groups/<int:pk>/", play.group_detail),
    path("squad/groups/join/<slug:slug>/", play.group_join),
    path("squad/games/<int:pk>/rsvp/", play.rsvp),
    path("squad/friends/", play.friends),
    path("squad/friends/<int:user_id>/add/", play.add_friend),
    path("squad/requests/", play.friend_requests),
    path("squad/requests/<int:pk>/<str:action>/", play.friend_request_action),
    path("squad/nearby/", play.nearby),
    # play
    path("play/home/", play.play_home),
    path("play/plan/", play.plan),
    path("play/games/", play.create_game),
    path("play/tournaments/", play.tournaments),
    path("play/tournaments/<int:pk>/", play.tournament_detail),
    path("play/tournaments/<int:pk>/register/", play.tournament_register),
    path("play/tournaments/<int:pk>/teams/", play.tournament_add_team),
    path("play/tournaments/<int:pk>/teams/<int:team_id>/pay/", play.team_pay),
    path("play/tournaments/<int:pk>/generate/", play.tournament_generate),
    path("play/tournaments/<int:pk>/remind/", play.tournament_remind),
    path("play/fixtures/<int:pk>/<str:action>/", play.fixture_action),
]

urlpatterns = [
    path("", lambda r: redirect("dashboard:home")),
    path("api/v1/", include(api)),
    path("admin-panel/", include("dashboard.urls")),
    path("django-admin/", admin.site.urls),
] + static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
