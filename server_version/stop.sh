#!/usr/bin/env bash
set -Eeuo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$BASE_DIR"
# shellcheck disable=SC1091
source "$BASE_DIR/runtime-lib.sh"
ensure_runtime_tree
exec 9>"$BASE_DIR/.runtime/lifecycle.lock"
acquire_lifecycle_lock_for_shutdown
cleanup_runtime
cleanup_transient_files
echo "HSLL Linux 客户端、Openbox、noVNC、x11vnc 和 Xvfb 已停止。"
