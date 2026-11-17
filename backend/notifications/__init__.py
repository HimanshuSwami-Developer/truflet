"""Notifications service: in-app notifications, device tokens and push delivery.

Other apps never import this app's models. They talk to it only through `notifications.service`
with plain values (user ids, strings), so the whole package can later run as its own microservice:
swap `LocalNotificationService` for an HTTP/queue client and nothing else changes.
"""
