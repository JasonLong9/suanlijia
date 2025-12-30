from django.contrib.auth import get_user_model
import sys

try:
    User = get_user_model()
    username = 'Administrator'
    password = 'Aa123456!'
    email = 'admin@example.com'

    if User.objects.filter(username=username).exists():
        u = User.objects.get(username=username)
        u.set_password(password)
        u.is_staff = True
        u.is_superuser = True
        u.save()
        print(f"SUCCESS: User {username} updated with new password.")
    else:
        User.objects.create_superuser(username, email, password)
        print(f"SUCCESS: User {username} created.")
except Exception as e:
    print(f"ERROR: {e}")
