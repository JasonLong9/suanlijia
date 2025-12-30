import os
import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "cp_server.settings")
django.setup()

from django.contrib.auth.models import User

username = "slc_node_v11"
password = "slc_node_v11_password_2025"
email = "slc_node_v11@example.com"

if not User.objects.filter(username=username).exists():
    User.objects.create_user(username=username, password=password, email=email)
    print(f"User {username} created successfully.")
else:
    print(f"User {username} already exists.")
