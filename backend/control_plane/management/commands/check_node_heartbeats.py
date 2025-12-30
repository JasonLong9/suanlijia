"""
Management command to detect and mark stale nodes as OFFLINE.

This command should be run periodically (e.g., every 30 seconds via cron or systemd timer)
to detect nodes that have stopped sending heartbeats and mark them as OFFLINE.

Usage:
    python manage.py check_node_heartbeats

    With custom timeout (default is 60 seconds):
    python manage.py check_node_heartbeats --timeout=90

    Run continuously in daemon mode:
    python manage.py check_node_heartbeats --daemon --interval=30
"""

import time
from datetime import timedelta
from django.core.management.base import BaseCommand
from django.utils import timezone

from control_plane.models import Node, NodeStatus
from control_plane.services.lease_lifecycle import mark_node_offline_and_end_leases


class Command(BaseCommand):
    help = 'Check node heartbeats and mark stale nodes as OFFLINE'

    def add_arguments(self, parser):
        parser.add_argument(
            '--timeout',
            type=int,
            default=60,
            help='Seconds after which a node is considered stale (default: 60)'
        )
        parser.add_argument(
            '--daemon',
            action='store_true',
            help='Run continuously in daemon mode'
        )
        parser.add_argument(
            '--interval',
            type=int,
            default=30,
            help='Check interval in seconds when running in daemon mode (default: 30)'
        )

    def handle(self, *args, **options):
        timeout = options['timeout']
        daemon = options['daemon']
        interval = options['interval']

        if daemon:
            self.stdout.write(self.style.SUCCESS(
                f'Starting heartbeat checker daemon (timeout={timeout}s, interval={interval}s)'
            ))
            while True:
                self._check_stale_nodes(timeout)
                time.sleep(interval)
        else:
            self._check_stale_nodes(timeout)

    def _check_stale_nodes(self, timeout_seconds: int):
        """Check for stale nodes and mark them as OFFLINE."""
        now = timezone.now()
        threshold = now - timedelta(seconds=timeout_seconds)

        # Find nodes that are not OFFLINE but haven't sent a heartbeat recently
        stale_nodes = Node.objects.filter(
            last_seen__lt=threshold
        ).exclude(
            status=NodeStatus.OFFLINE
        )

        count = 0
        for node in stale_nodes:
            old_status = node.status
            seconds_since_seen = (now - node.last_seen).total_seconds()
            
            self.stdout.write(
                f'[HEARTBEAT] Node {node.device_id} stale: '
                f'last_seen={node.last_seen}, seconds_ago={seconds_since_seen:.0f}, '
                f'status={old_status} -> OFFLINE'
            )
            
            # Use existing function to properly end leases and mark offline
            mark_node_offline_and_end_leases(
                device_id=node.device_id,
                reason='heartbeat_timeout'
            )
            count += 1

        if count > 0:
            self.stdout.write(self.style.SUCCESS(
                f'Marked {count} stale node(s) as OFFLINE'
            ))
