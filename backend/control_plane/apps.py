from django.apps import AppConfig
from django.db.backends.signals import connection_created


class ControlPlaneConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "control_plane"

    def ready(self):
        def _set_sqlite_pragmas(sender, connection, **kwargs):
            if connection.vendor != "sqlite":
                return
            try:
                cursor = connection.cursor()
                cursor.execute("PRAGMA journal_mode=WAL;")
                cursor.execute("PRAGMA synchronous=NORMAL;")
                cursor.execute("PRAGMA foreign_keys=ON;")
                cursor.close()
            except Exception:
                # Best-effort for local dev.
                return

        connection_created.connect(_set_sqlite_pragmas, dispatch_uid="cp_sqlite_pragmas")
