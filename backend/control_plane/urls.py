from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView

from . import views


urlpatterns = [
    # Downloads
    path("download/", views.DownloadPageView.as_view()),
    path("download/pool-node/", views.DownloadPoolNodeView.as_view()),
    path("download/official/", views.DownloadOfficialView.as_view()),
    path("download/gui/", views.DownloadGUIView.as_view()),
    path("download/v12.2/", views.DownloadV122View.as_view()),
    # Auth (legacy-compatible for current Flutter client)
    path("register/", views.RegisterView.as_view()),
    path("login/", views.LoginView.as_view()),
    path("token/refresh/", TokenRefreshView.as_view()),
    path("tokenlogin/", views.TokenLoginView.as_view()),
    path("requestnickname/", views.RequestNicknameView.as_view()),
    path("updateuserinfo/", views.UpdateUserInfoView.as_view()),
    path("getlatestversion/", views.GetLatestVersionView.as_view()),
    # Control plane (OpenAPI)
    path("pool/nodes/", views.PoolNodesView.as_view()),
    path("lease/rent/", views.RentLeaseView.as_view()),
    path("lease/release/", views.ReleaseLeaseView.as_view()),
    path("lease/list/", views.LeaseListView.as_view()),
    path("billing/info/", views.BillingInfoView.as_view()),
    path("device/token/", views.DeviceTokenView.as_view()),
    # Admin
    path("admin/nodes/", views.AdminNodesView.as_view()),
    path("admin/nodes/<str:device_id>/", views.AdminUpdateNodeView.as_view()),
    path("admin/nodes/<str:device_id>/state/", views.AdminSetNodeStateView.as_view()),
    path(
        "admin/nodes/<str:device_id>/force_release/",
        views.AdminForceReleaseNodeView.as_view(),
    ),
    path(
        "admin/leases/<uuid:lease_id>/force_release/",
        views.AdminForceReleaseLeaseView.as_view(),
    ),
    path("admin/nodes/<str:device_id>/reboot/", views.AdminRebootNodeView.as_view()),
    path("admin/nodes/<str:device_id>/delete/", views.AdminDeleteNodeView.as_view()),
    # Client debugging
    path("client/log/", views.ClientLogView.as_view()),
]
