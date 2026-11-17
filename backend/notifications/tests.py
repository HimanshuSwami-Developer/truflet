from unittest import mock

from django.contrib.auth import get_user_model
from django.test import TestCase
from rest_framework.test import APIClient

from . import service
from .channels import fcm
from .models import DeviceToken, Notification

User = get_user_model()


class DeviceTokenTests(TestCase):
    def setUp(self):
        self.a = User.objects.create_user("a@x.com", name="Ann", phone="+919800000011")
        self.b = User.objects.create_user("b@x.com", name="Ben", phone="+919800000012")
        self.api = APIClient()

    def test_register_moves_token_between_players_and_remove_needs_no_session(self):
        self.api.force_authenticate(self.a)
        self.assertEqual(self.api.post("/api/v1/devices/", {"token": "tok1", "platform": "android"}).status_code, 200)
        self.api.force_authenticate(self.b)
        self.api.post("/api/v1/devices/", {"token": "tok1", "platform": "android"})
        self.assertEqual(DeviceToken.objects.get(token="tok1").user, self.b)
        self.api.force_authenticate(None)
        self.assertEqual(self.api.post("/api/v1/devices/remove/", {"token": "tok1"}).status_code, 200)
        self.assertFalse(DeviceToken.objects.exists())

    def test_register_requires_sign_in(self):
        self.assertEqual(self.api.post("/api/v1/devices/", {"token": "tok1"}).status_code, 401)


class NotifyTests(TestCase):
    def setUp(self):
        self.a = User.objects.create_user("a@x.com", name="Ann", phone="+919800000011")
        self.b = User.objects.create_user("b@x.com", name="Ben", phone="+919800000012", notifications_on=False)

    def test_notify_saves_and_pushes_after_commit_unless_muted(self):
        with mock.patch.object(fcm, "send") as send, self.captureOnCommitCallbacks(execute=True):
            nid = service.notify(self.a.pk, "Hi", "there", "match")
        send.assert_called_once_with(self.a.pk, "Hi", "there", {"kind": "match", "notification_id": nid})
        with mock.patch.object(fcm, "send") as send, self.captureOnCommitCallbacks(execute=True):
            service.notify(self.b.pk, "Hi")
        send.assert_not_called()
        self.assertEqual(Notification.objects.filter(user=self.b).count(), 1)  # muted players still get it in-app

    def test_notify_without_a_user_is_a_no_op(self):
        self.assertIsNone(service.notify(None, "Hi"))
        self.assertFalse(Notification.objects.exists())

    def test_broadcast_and_list_api(self):
        self.assertEqual(service.broadcast([self.a.pk, self.b.pk], "Offer", "₹100 off"), 2)
        api = APIClient()
        api.force_authenticate(self.a)
        r = api.get("/api/v1/notifications/")
        self.assertEqual((r.data["unread"], r.data["items"][0]["kind"]), (1, "offer"))
        api.post("/api/v1/notifications/read/")
        self.assertEqual(api.get("/api/v1/notifications/").data["unread"], 0)

    def test_push_without_credentials_is_a_no_op(self):
        DeviceToken.objects.create(user=self.a, token="tok1")
        with mock.patch.object(fcm, "_load", return_value=None), mock.patch.object(fcm.requests, "post") as post:
            fcm.send(self.a.pk, "Hi")
        post.assert_not_called()
