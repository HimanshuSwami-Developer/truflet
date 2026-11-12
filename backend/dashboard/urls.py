from django.urls import path

from . import views as v

app_name = "dashboard"

urlpatterns = [
    path("", v.home, name="home"),
    path("login/", v.login_view, name="login"),
    path("login/code/", v.login_code_view, name="login_code"),
    path("logout/", v.logout_view, name="logout"),
    path("search/", v.api_search, name="search"),
    path("settings/", v.settings_view, name="settings"),
    path("broadcast/", v.broadcast, name="broadcast"),
    path("checkin/", v.checkin, name="checkin"),
    # detail pages
    path("venues/<int:pk>/", v.venue_detail, name="venue_detail"),
    path("venues/<int:pk>/board/", v.availability_board, name="availability"),
    path("venues/<int:pk>/photos/", v.venue_photo_upload, name="venue_photo_upload"),
    path("venues/<int:pk>/photos/<int:photo_id>/delete/", v.venue_photo_delete, name="venue_photo_delete"),
    path("bookings/<int:pk>/", v.booking_detail, name="booking_detail"),
    path("bookings/<int:pk>/<str:action>/", v.booking_action, name="booking_action"),
    path("users/<int:pk>/", v.user_detail, name="user_detail"),
    path("users/<int:pk>/wallet/", v.user_wallet, name="user_wallet"),
    path("tournaments/<int:pk>/", v.tournament_detail, name="tournament_detail"),
    path("tournaments/<int:pk>/generate/", v.tournament_generate, name="tournament_generate"),
    # generic CRUD
    path("r/<slug:slug>/", v.crud_list, name="crud_list"),
    path("r/<slug:slug>/new/", v.crud_form, name="crud_create"),
    path("r/<slug:slug>/<int:pk>/edit/", v.crud_form, name="crud_edit"),
    path("r/<slug:slug>/<int:pk>/delete/", v.crud_delete, name="crud_delete"),
    path("r/<slug:slug>/<int:pk>/toggle/<str:field>/", v.crud_toggle, name="crud_toggle"),
]
