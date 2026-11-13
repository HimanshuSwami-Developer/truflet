from unittest import mock

from django.contrib.auth import get_user_model
from django.test import TestCase
from rest_framework.test import APIClient

from .models import DeviceToken, notify

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

    def test_notify_pushes_after_commit_unless_muted(self):
        with mock.patch("core.push.send_push") as send, self.captureOnCommitCallbacks(execute=True):
            n = notify(self.a, "Hi", "there", "match")
        send.assert_called_once_with(n)
        self.b.notifications_on = False
        self.b.save()
        with mock.patch("core.push.send_push") as send, self.captureOnCommitCallbacks(execute=True):
            notify(self.b, "Hi")
        send.assert_not_called()

    def test_send_push_without_credentials_is_a_no_op(self):
        from . import push

        DeviceToken.objects.create(user=self.a, token="tok1")
        with mock.patch.object(push, "_load", return_value=None), mock.patch.object(push.requests, "post") as post:
            push.send_push(notify(self.a, "Hi"))
        post.assert_not_called()
