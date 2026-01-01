#!/usr/bin/env bash
set -euo pipefail

# 用途：快速回滚 /var/www/cloudplayplus/web 到指定目录（或软链接目标）。
#
# 用法：
#   scripts/rollback_web.sh /var/www/cloudplayplus/web_prev_20260101_021525
#

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  echo "Usage: $0 <target_web_dir_or_symlink>" >&2
  exit 2
fi

WEB_BASE_DIR="${WEB_BASE_DIR:-/var/www/cloudplayplus}"
WEB_LINK="${WEB_LINK:-$WEB_BASE_DIR/web}"
NGINX_BIN="${NGINX_BIN:-/usr/local/nginx/sbin/nginx}"

if [[ ! -e "$TARGET" ]]; then
  echo "ERROR: target not found: $TARGET" >&2
  exit 1
fi

ln -sfn "$TARGET" "$WEB_LINK"
echo "[rollback] switched: $WEB_LINK -> $(readlink -f "$WEB_LINK")"

if [[ -x "$NGINX_BIN" ]]; then
  "$NGINX_BIN" -s reload
  echo "[rollback] nginx reloaded"
else
  echo "[rollback] WARN: nginx binary not found/executable at: $NGINX_BIN" >&2
fi

if [[ -f "$WEB_LINK/version.json" ]]; then
  echo "[rollback] version.json:"
  cat "$WEB_LINK/version.json"
fi

