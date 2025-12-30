# Repository Guidelines

## Project Structure & Module Organization
- `lib/`: Flutter/Dart application code (see `blocs/`, `pages/`, `services/`, `widgets/`, `utils/`).
- `backend/`: Django 控制平面（资源池/租赁/计费/管理台 + WebSocket 信令转发）。
- `plugins/`: vendored plugin forks and git submodules (notably custom `flutter-webrtc/` + `dart-webrtc/`).
- `assets/`: images, cursors, and fonts used by the app.
- `test/`: unit/widget tests (`*_test.dart`).
- Platform shells: `android/`, `ios/`, `macos/`, `windows/`, `linux/`, `web/`.
- CI config: `.github/workflows/build-all.yml`.

## Build, Test, and Development Commands
Prereq: Flutter SDK (CI pins `3.35.1`).

- Clone with submodules: `git clone --recurse-submodules <repo>` (or `git submodule update --init --recursive`).
- Install dependencies (root + plugins):
  - `flutter pub get`
  - `find plugins -maxdepth 2 -name pubspec.yaml -print0 | while IFS= read -r -d '' f; do (cd "$(dirname "$f")" && flutter pub get); done`
- Start backend (local): `python3 -m pip install -r backend/requirements.txt && python3 backend/manage.py migrate && python3 backend/manage.py runserver 0.0.0.0:8000 --noreload`
- Run locally: `flutter run -d windows|macos|linux|chrome|android`.
- Build: `flutter build windows|macos|linux`, `flutter build web --release`, `flutter build apk --release --android-skip-build-dependency-validation`.
- Serve built web (CORS): `flutter build web --release` then `python3 run.py` (serves `build/web` on `http://0.0.0.0:8000`).

## Coding Style & Naming Conventions
- Dart/Flutter: use standard dartfmt (2-space indentation); prefer trailing commas where appropriate.
- Formatting: `dart format .`
- Linting: `flutter analyze` (rules from `analysis_options.yaml` via `flutter_lints`).

## Testing Guidelines
- Framework: `flutter_test`.
- Naming: `test/**/*_test.dart`.
- Run all tests: `flutter test`; run one file: `flutter test test/smooth_mouse_controller_test.dart`.
- Keep tests deterministic; avoid adding new tests that require live network or device hardware when possible.

## Commit & Pull Request Guidelines
- Commit history uses short subjects (English/Chinese), often starting with verbs (e.g., “fix…”, “refactor…”) and sometimes an issue ref like `(#80)`.
- Keep commits scoped; include the issue/PR number when applicable (prefixes like `fix:`/`feat:` are welcome but not required).
- PRs should include: a clear description, platforms tested (e.g., Windows/Web), and screenshots/recordings for UI changes. If you update anything under `plugins/`, call out submodule pointer changes explicitly.

## Configuration Tips
- If you’re in mainland China, CI uses mirrors: `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn` and `PUB_HOSTED_URL=https://pub.flutter-io.cn`.
