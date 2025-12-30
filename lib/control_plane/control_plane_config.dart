class ControlPlaneConfig {
  static const bool useMock =
      bool.fromEnvironment('CPP_CONTROL_PLANE_MOCK', defaultValue: false);
}
