from django.core.management.base import BaseCommand
from django.contrib.auth.hashers import make_password

from control_plane.models import Node, NodeStatus


class Command(BaseCommand):
    help = "Create/update a GPU node (device_id + device_secret) for Node Mode."

    def add_arguments(self, parser):
        parser.add_argument("--device-id", required=True)
        parser.add_argument("--device-secret", required=True)
        parser.add_argument("--region", default="")
        parser.add_argument("--gpu-tier", default="")

    def handle(self, *args, **options):
        device_id = options["device_id"]
        device_secret = options["device_secret"]
        region = options["region"]
        gpu_tier = options["gpu_tier"]

        node, created = Node.objects.get_or_create(device_id=device_id)
        node.device_secret_hash = make_password(device_secret)
        if region:
            node.region = region
        if gpu_tier:
            node.gpu_tier = gpu_tier
        if node.status == NodeStatus.OFFLINE:
            node.status = NodeStatus.OFFLINE
        node.save()

        action = "created" if created else "updated"
        self.stdout.write(self.style.SUCCESS(f"Node {action}: {device_id}"))

