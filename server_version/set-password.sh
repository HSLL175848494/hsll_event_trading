#!/usr/bin/env bash
set -Eeuo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$BASE_DIR"
# shellcheck disable=SC1091
source "$BASE_DIR/runtime-lib.sh"

command -v x11vnc >/dev/null 2>&1 || { echo "缺少 x11vnc，请先执行 sudo bash install.sh"; exit 1; }
[[ -t 0 ]] || { echo "请在交互终端中运行 bash set-password.sh"; exit 1; }

read -r -s -p "请输入新的 VNC 密码（6~8 位）: " password
echo
read -r -s -p "请再次输入: " confirmation
echo
[[ "$password" == "$confirmation" ]] || { echo "两次密码不一致。"; exit 1; }
((${#password} >= 6 && ${#password} <= 8)) || {
  echo "经典 VNC 协议仅使用前 8 位，请设置 6~8 位密码。"
  exit 1
}

ensure_runtime_tree
exec 9>"$BASE_DIR/.runtime/lifecycle.lock"
acquire_lifecycle_lock_for_shutdown
cleanup_runtime

temporary="$BASE_DIR/data/.vnc.pass.tmp-$$"
trap 'rm -f -- "$temporary"' EXIT INT TERM
x11vnc -storepasswd "$password" "$temporary" >/dev/null
chmod 600 "$temporary"
mv -f -- "$temporary" "$BASE_DIR/data/vnc.pass"
trap - EXIT INT TERM
unset password confirmation

echo "VNC 密码已更新。"
echo "启动: bash start.sh"
