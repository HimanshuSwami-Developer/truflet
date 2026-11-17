from django.contrib.auth import get_user_model
from django.test import TestCase


User = get_user_model()


class PrivacyPageTests(TestCase):
    def test_public_privacy_page_and_config_link(self):
        r = self.client.get("/privacy/")
        self.assertEqual(r.status_code, 200)
        self.assertContains(r, "Privacy Policy")
        self.assertContains(r, "Deleting your account")
        self.assertNotContains(r, "+918000000000")
        self.assertTrue(self.client.get("/api/v1/config/").json()["privacy_url"].endswith("/privacy/"))
