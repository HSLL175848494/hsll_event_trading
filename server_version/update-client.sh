#!/usr/bin/env bash
set -Eeuo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$BASE_DIR"
# shellcheck disable=SC1091
source "$BASE_DIR/runtime-lib.sh"

if [[ $# -ne 1 ]]; then
  echo "用法: bash update-client.sh /path/to/hsll-order-reminder-vX.Y.Z.AppImage"
  exit 2
fi
source_file=$(readlink -f -- "$1" 2>/dev/null || true)
[[ -n "$source_file" && -f "$source_file" ]] || { echo "客户端文件不存在: $1"; exit 1; }
is_linux_appimage "$source_file" || {
  echo "文件不是有效的 Linux AppImage；Windows exe 或普通 ELF 不能安装。" >&2
  exit 1
}

ensure_runtime_tree
exec 9>"$BASE_DIR/.runtime/lifecycle.lock"
acquire_lifecycle_lock_for_shutdown
cleanup_runtime
cleanup_transient_files

temporary="$BASE_DIR/app/.client.AppImage.tmp-$$"
trap 'rm -f -- "$temporary"' EXIT INT TERM
cp -- "$source_file" "$temporary"
chmod 700 "$temporary"
mv -f -- "$temporary" "$BASE_DIR/app/client.AppImage"
trap - EXIT INT TERM

echo "Linux 客户端已更新: app/client.AppImage"
echo "启动: bash start.sh"
