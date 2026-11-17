"""Hands Notification and DeviceToken over to the `notifications` app (state only — the tables stay)."""
from django.db import migrations


class Migration(migrations.Migration):
    dependencies = [
        ("core", "0005_device_token"),
        ("notifications", "0001_initial"),
    ]

    operations = [
        migrations.SeparateDatabaseAndState(
            database_operations=[],
            state_operations=[
                migrations.DeleteModel(name="Notification"),
                migrations.DeleteModel(name="DeviceToken"),
            ],
        ),
    ]
