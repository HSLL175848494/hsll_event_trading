#!/usr/bin/env bash
set -Eeuo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
[[ "$BASE_DIR" != / && -f "$BASE_DIR/runtime-lib.sh" && -f "$BASE_DIR/start.sh" ]] || {
  echo "项目目录校验失败，拒绝卸载。"
  exit 1
}
cd "$BASE_DIR"
# shellcheck disable=SC1091
source "$BASE_DIR/runtime-lib.sh"
case "${1:-}" in
  ''|--purge-data) ;;
  *) echo "用法: bash uninstall.sh [--purge-data]"; exit 2 ;;
esac

ensure_runtime_tree
exec 9>"$BASE_DIR/.runtime/lifecycle.lock"
acquire_lifecycle_lock_for_shutdown
cleanup_runtime
cleanup_transient_files

if [[ "${1:-}" == "--purge-data" ]]; then
  flock -u 9
  exec 9>&-
  rm -rf -- "$BASE_DIR/data" "$BASE_DIR/logs" "$BASE_DIR/.runtime"
  rm -f -- "$BASE_DIR/config.env"
  echo "客户端配置、登录状态、VNC 密码和日志已删除；AppImage 与启动脚本保留。"
else
  flock -u 9
  exec 9>&-
  rm -rf -- "$BASE_DIR/.runtime"
  echo "运行进程和临时文件已清理；客户端配置、登录状态、VNC 密码及 AppImage 均保留。"
  echo "彻底删除运行数据: bash uninstall.sh --purge-data"
fi
