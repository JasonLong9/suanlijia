import os

from channels.routing import ProtocolTypeRouter, URLRouter
from django.core.asgi import get_asgi_application

import cp_server.routing


os.environ.setdefault("DJANGO_SETTINGS_MODULE", "cp_server.settings")

django_asgi_app = get_asgi_application()

application = ProtocolTypeRouter(
    {
        "http": django_asgi_app,
        "websocket": URLRouter(cp_server.routing.websocket_urlpatterns),
    }
)

