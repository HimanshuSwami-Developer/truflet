"""Firebase Cloud Messaging (HTTP v1) sender.

Configure one of:
  FIREBASE_SERVICE_ACCOUNT       the service-account JSON itself (handy on Vercel)
  FIREBASE_SERVICE_ACCOUNT_FILE  path to the service-account JSON file
Without either, pushes are skipped and in-app notifications still work.
"""

import json
import logging
import os
import threading

import requests

log = logging.getLogger(__name__)

_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
_lock = threading.Lock()
_credentials = None
_project_id = None
_loaded = False


def _load():
    global _credentials, _project_id, _loaded
    with _lock:
        if _loaded:
            return _credentials
        _loaded = True
        raw = os.getenv("FIREBASE_SERVICE_ACCOUNT")
        path = os.getenv("FIREBASE_SERVICE_ACCOUNT_FILE")
        try:
            if raw:
                info = json.loads(raw)
            elif path:
                with open(path) as f:
                    info = json.load(f)
            else:
                log.info("FCM: no FIREBASE_SERVICE_ACCOUNT configured, pushes disabled")
                return None
            from google.oauth2 import service_account

            _credentials = service_account.Credentials.from_service_account_info(info, scopes=[_SCOPE])
            _project_id = info["project_id"]
        except Exception:
            log.exception("FCM: could not load the service account, pushes disabled")
            _credentials = None
        return _credentials


def _access_token(creds):
    from google.auth.transport.requests import Request

    with _lock:
        if not creds.valid:
            creds.refresh(Request())
        return creds.token


def send_push(notification):
    """Sends a saved Notification to every device of its player. Never raises."""
    from .models import DeviceToken

    try:
        creds = _load()
        if creds is None:
            return
        tokens = list(DeviceToken.objects.filter(user_id=notification.user_id).values_list("token", flat=True))
        if not tokens:
            return
        headers = {"Authorization": f"Bearer {_access_token(creds)}"}
        url = f"https://fcm.googleapis.com/v1/projects/{_project_id}/messages:send"
        for token in tokens:
            body = {"message": {
                "token": token,
                "notification": {"title": notification.title, "body": notification.body or ""},
                "data": {"kind": notification.kind, "notification_id": str(notification.pk)},
                "android": {"priority": "high", "notification": {
                    "channel_id": "turflet_alerts", "icon": "ic_notification", "color": "#143D2B"}},
            }}
            r = requests.post(url, json=body, headers=headers, timeout=5)
            if r.status_code in (400, 404) and ("UNREGISTERED" in r.text or "INVALID_ARGUMENT" in r.text):
                DeviceToken.objects.filter(token=token).delete()  # app uninstalled / token rotated
            elif r.status_code >= 300:
                log.warning("FCM send failed (%s): %s", r.status_code, r.text[:300])
    except Exception:
        log.exception("FCM: push failed")
