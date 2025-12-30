# Changelog

All notable changes to this project will be documented in this file.

## [v1.0.0-beta] - 2025-12-27
### Changed
- **Version Bump**: Rebranded v10.3 as v1.0.0-beta to mark the first stable public beta release.

### Fixed
- **Node Agent URL Mismatch**: Fixed a critical issue where the Node Agent would connect to the default production server (`cloudplayplus.com`) instead of the custom `api_url` defined in `node.json`.
- **Implementation**: Modified `WebSocketService` to explicitly prioritize `NodeAgentConfig.apiUrl` over `AppConfig` defaults in Node Mode.

## [v10.2] - 2025-12-27
### Fixed
- **Headless Mode Hang**: Resolved a blocking issue where the Node Agent would hang indefinitely on startup in headless mode.
- **Root Cause**: Removed calls to `SharedPreferences` (which requires Flutter UI bindings) during the headless initialization sequence.
- **Logging**: Implemented direct file logging to `C:\ProgramData\SLC\logs\startup.log` using `dart:io` to ensure visibility even when the main logging system is not fully initialized.

## [v10.1] - 2025-12-26
### Changed
- **Dependency Management**: Optimized dependencies for headless mode to reduce binary size and startup time.
- **Installation Script**: Improved `install_node_service_silent.bat` to better detect public IP and city information.

## [v10.0] - 2025-12-25
### Added
- **Initial Node Agent Release**: First stable release of the Windows Node Agent service.
- **Features**: Support for headless operation, automatic updates, and remote control session management.
