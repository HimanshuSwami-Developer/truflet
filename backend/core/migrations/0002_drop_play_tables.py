"""Squad, quick match and tournaments were removed: drop the old `play` app's tables.

The play app no longer exists in code, so its tables are dropped by name. Safe on databases
that never had them. Also clears play's content types / permissions and migration history.
This cannot be reversed — the data is gone.
"""
from django.db import migrations

PLAY_TABLES = [
    # children first, so it also works on SQLite (no CASCADE)
    "play_fixture",
    "play_tournamentteam",
    "play_tournament",
    "play_rsvp",
    "play_game",
    "play_groupmember",
    "play_friendrequest",
    "play_group",
]


def drop_play(apps, schema_editor):
    conn = schema_editor.connection
    existing = set(conn.introspection.table_names())
    cascade = " CASCADE" if conn.vendor == "postgresql" else ""
    with conn.cursor() as cur:
        for table in PLAY_TABLES:
            if table in existing:
                cur.execute(f"DROP TABLE {schema_editor.quote_name(table)}{cascade}")
        cur.execute("DELETE FROM django_migrations WHERE app = %s", ["play"])
    ContentType = apps.get_model("contenttypes", "ContentType")
    ContentType.objects.filter(app_label="play").delete()  # cascades to auth permissions


class Migration(migrations.Migration):
    dependencies = [
        ("core", "0001_initial"),
        ("contenttypes", "0002_remove_content_type_name"),
        ("auth", "0012_alter_user_first_name_max_length"),
    ]
    operations = [migrations.RunPython(drop_play, migrations.RunPython.noop)]
