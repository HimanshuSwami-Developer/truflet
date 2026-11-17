"""Takes over the Notification and DeviceToken models from `core`.

State-only: the tables `core_notification` and `core_devicetoken` already exist and keep their
names and data. Nothing is created or altered in the database.
"""
import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):
    initial = True

    dependencies = [
        ("core", "0005_device_token"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.SeparateDatabaseAndState(
            database_operations=[],
            state_operations=[
                migrations.CreateModel(
                    name="Notification",
                    fields=[
                        ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                        ("kind", models.CharField(choices=[("booking", "Booking"), ("match", "Match"), ("offer", "Offer"), ("system", "System")], default="system", max_length=20)),
                        ("title", models.CharField(max_length=120)),
                        ("body", models.CharField(blank=True, max_length=255)),
                        ("is_read", models.BooleanField(default=False)),
                        ("created_at", models.DateTimeField(auto_now_add=True)),
                        ("updated_at", models.DateTimeField(auto_now=True)),
                        ("user", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="notifications", to=settings.AUTH_USER_MODEL)),
                    ],
                    options={"db_table": "core_notification", "ordering": ["-created_at"]},
                ),
                migrations.CreateModel(
                    name="DeviceToken",
                    fields=[
                        ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                        ("token", models.CharField(max_length=512, unique=True)),
                        ("platform", models.CharField(blank=True, max_length=20)),
                        ("created_at", models.DateTimeField(auto_now_add=True)),
                        ("updated_at", models.DateTimeField(auto_now=True)),
                        ("user", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="devices", to=settings.AUTH_USER_MODEL)),
                    ],
                    options={"db_table": "core_devicetoken"},
                ),
            ],
        ),
    ]
