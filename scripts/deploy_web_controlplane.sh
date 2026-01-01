#!/usr/bin/env bash
set -euo pipefail

# 用途：构建并发布「旧版资源池/租赁 Web」+「远控顶部统计栏」的稳定版本，
#      通过原子切换 /var/www/cloudplayplus/web 符号链接避免“误覆盖导致功能丢失”。
#
# 用法：
#   scripts/deploy_web_controlplane.sh [build_name] [build_number]
#
# 示例：
#   scripts/deploy_web_controlplane.sh 1.0.1-beta 202601011535
#
# 约定：
# - Nginx root 固定指向 /var/www/cloudplayplus/web（建议保持为 symlink）
# - 每次发布生成一个独立目录（带版本号），并保留 web_prev_* 软链接用于回滚

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BUILD_NAME="${1:-1.0.1-beta}"
BUILD_NUMBER="${2:-$(date +%Y%m%d%H%M%S)}"
PWA_STRATEGY="${PWA_STRATEGY:-none}"

OUT_DIR="$ROOT_DIR/build/web_cp_${BUILD_NAME}_${BUILD_NUMBER}"

WEB_BASE_DIR="${WEB_BASE_DIR:-/var/www/cloudplayplus}"
WEB_LINK="${WEB_LINK:-$WEB_BASE_DIR/web}"
NGINX_BIN="${NGINX_BIN:-/usr/local/nginx/sbin/nginx}"

# 复用已有的大体积下载目录（可按需改成独立的 downloads_shared）
DOWNLOADS_SHARED="${DOWNLOADS_SHARED:-$WEB_BASE_DIR/web_newsystem_20260101_140639/downloads}"

echo "[deploy] build_name=${BUILD_NAME} build_number=${BUILD_NUMBER}"
echo "[deploy] out_dir=${OUT_DIR}"

cd "$ROOT_DIR"

flutter build web \
  --release \
  --pwa-strategy="$PWA_STRATEGY" \
  --no-wasm-dry-run \
  --optimization-level=2 \
  --build-name="$BUILD_NAME" \
  --build-number="$BUILD_NUMBER" \
  -o "$OUT_DIR"

echo "[deploy] verify build artifacts..."

MAIN_JS="$OUT_DIR/main.dart.js"
if ! rg -q "/api/pool/nodes/" "$MAIN_JS"; then
  echo "[deploy] ERROR: build missing control-plane markers (/api/pool/nodes/)" >&2
  exit 1
fi
if ! rg -q "/api/lease/list/" "$MAIN_JS"; then
  echo "[deploy] ERROR: build missing leases markers (/api/lease/list/)" >&2
  exit 1
fi
if ! rg -q "/api/billing/info/" "$MAIN_JS"; then
  echo "[deploy] ERROR: build missing billing markers (/api/billing/info/)" >&2
  exit 1
fi
if ! rg -q "requestRemoteControlLease" "$MAIN_JS"; then
  echo "[deploy] ERROR: build missing lease-remote-control markers (requestRemoteControlLease)" >&2
  exit 1
fi
if ! rg -q "\\| RTT" "$MAIN_JS"; then
  echo "[deploy] ERROR: build missing streaming-stats markers (| RTT)" >&2
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
RELEASE_DIR="$WEB_BASE_DIR/web_cp_${BUILD_NAME}_${BUILD_NUMBER}_${TS}"

echo "[deploy] release_dir=${RELEASE_DIR}"
mkdir -p "$RELEASE_DIR"

echo "[deploy] copying (excluding downloads)..."
tar --exclude='./downloads' -C "$OUT_DIR" -cf - . | tar -C "$RELEASE_DIR" -xf -

if [[ -d "$DOWNLOADS_SHARED" ]]; then
  ln -s "$DOWNLOADS_SHARED" "$RELEASE_DIR/downloads"
else
  echo "[deploy] WARN: DOWNLOADS_SHARED not found, copying downloads..."
  cp -a "$OUT_DIR/downloads" "$RELEASE_DIR/downloads"
fi

{
  echo "build_name=${BUILD_NAME}"
  echo "build_number=${BUILD_NUMBER}"
  echo "timestamp=${TS}"
  echo "git_head=$(git rev-parse HEAD 2>/dev/null || echo unknown)"
} > "$RELEASE_DIR/build_info.txt"

CURRENT_TARGET="$(readlink -f "$WEB_LINK" 2>/dev/null || true)"
if [[ -n "${CURRENT_TARGET}" ]]; then
  ln -s "$CURRENT_TARGET" "$WEB_BASE_DIR/web_prev_${TS}"
  echo "[deploy] backup: $WEB_BASE_DIR/web_prev_${TS} -> ${CURRENT_TARGET}"
fi

ln -sfn "$RELEASE_DIR" "$WEB_LINK"
echo "[deploy] switched: $WEB_LINK -> $(readlink -f "$WEB_LINK")"

if [[ -x "$NGINX_BIN" ]]; then
  "$NGINX_BIN" -s reload
  echo "[deploy] nginx reloaded"
else
  echo "[deploy] WARN: nginx binary not found/executable at: $NGINX_BIN" >&2
fi

echo "[deploy] done. version.json:"
cat "$WEB_LINK/version.json"
