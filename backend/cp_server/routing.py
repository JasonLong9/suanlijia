from django.urls import path

from control_plane.consumers import ControlPlaneConsumer


websocket_urlpatterns = [
    path("ws/", ControlPlaneConsumer.as_asgi()),
]

