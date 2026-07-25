#!/usr/bin/env bash
set -Eeuo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$BASE_DIR"
# shellcheck disable=SC1091
source "$BASE_DIR/runtime-lib.sh"

if [[ ${EUID} -eq 0 ]]; then
  echo "请使用普通用户运行 bash start.sh；Electron 不应以 root 身份启动。" >&2
  exit 1
fi

load_config
ensure_runtime_tree
exec 9>"$BASE_DIR/.runtime/lifecycle.lock"
if ! flock -n 9; then echo "另一个启动、停止、更新或卸载操作正在执行。"; exit 1; fi

client_pid=$(pid_from_file client 2>/dev/null || true)
if [[ -n "$client_pid" ]] && process_matches client "$client_pid"; then
  echo "HSLL Linux 客户端投影已经运行。"
  bash "$BASE_DIR/status.sh"
  exit 0
fi

cleanup_runtime
cleanup_transient_files

for command in Xvfb openbox x11vnc websockify setsid ss od; do
  command -v "$command" >/dev/null 2>&1 || { echo "缺少运行命令: $command，请先执行 sudo bash install.sh"; exit 1; }
done
[[ -f /usr/share/novnc/vnc.html ]] || { echo "未找到 /usr/share/novnc/vnc.html，请重新执行 sudo bash install.sh"; exit 1; }

CLIENT_APP="$BASE_DIR/app/client.AppImage"
is_linux_appimage "$CLIENT_APP" || {
  echo "未安装有效的 Linux AppImage: $CLIENT_APP" >&2
  echo "请先执行: bash update-client.sh /path/to/hsll-order-reminder-v1.1.0.AppImage" >&2
  exit 1
}
[[ -r "$BASE_DIR/data/vnc.pass" && ! -L "$BASE_DIR/data/vnc.pass" ]] || {
  echo "VNC 密码文件不存在，请执行 bash set-password.sh" >&2
  exit 1
}

for port in 5900 "$WEB_PORT"; do
  if port_in_use "$port"; then echo "端口 $port 已被非本项目进程占用，启动已中止。"; exit 1; fi
done

display=''
for number in {90..109}; do
  if [[ ! -e "/tmp/.X11-unix/X$number" && ! -e "/tmp/.X$number-lock" ]]; then display=":$number"; break; fi
done
[[ -n "$display" ]] || { echo "没有可用的 Xvfb 显示编号（:90~:109）。"; exit 1; }
printf '%s\n' "$display" > "$BASE_DIR/.runtime/display"

export HOME="$BASE_DIR/data/home"
export TMPDIR="$BASE_DIR/data/tmp"
export XDG_CONFIG_HOME="$BASE_DIR/data/xdg-config"
export XDG_CACHE_HOME="$BASE_DIR/data/xdg-cache"
export XDG_STATE_HOME="$BASE_DIR/data/xdg-state"

start_component() {
  local name="$1" log="$2"; shift 2
  prepare_log "$log"
  nohup setsid env \
    HSLL_PROJECT_ROOT="$BASE_DIR" \
    HSLL_COMPONENT="$name" \
    "$@" >> "$BASE_DIR/logs/$log" 2>&1 9>&- &
  printf '%s\n' "$!" > "$BASE_DIR/.runtime/$name.pid"
}

failed=1
trap 'if [[ $failed -ne 0 ]]; then echo "启动未完成，清理本次启动的进程。"; cleanup_runtime || true; fi' EXIT INT TERM

start_component xvfb xvfb.log \
  Xvfb "$display" -screen 0 "${SCREEN_WIDTH}x${SCREEN_HEIGHT}x24" -nolisten tcp -noreset
sleep 0.5
start_component openbox openbox.log env DISPLAY="$display" openbox --sm-disable
start_component x11vnc x11vnc.log \
  x11vnc -display "$display" -rfbport 5900 -localhost -forever -shared -rfbauth "$BASE_DIR/data/vnc.pass"
start_component novnc novnc.log \
  websockify --web=/usr/share/novnc "$WEB_HOST:$WEB_PORT" 127.0.0.1:5900

wait_for_port "$WEB_PORT" || { echo "noVNC 启动超时，请查看 logs/novnc.log"; exit 1; }

# APPIMAGE_EXTRACT_AND_RUN avoids depending on FUSE on minimal cloud images.
# A user-extracted AppImage cannot retain a root-owned setuid chrome-sandbox,
# so --no-sandbox is required for this dedicated remote projection process.
# password-store=basic makes Electron safeStorage usable without a desktop keyring;
# project data remains permission-restricted to the service account.
start_component client client.log \
  env DISPLAY="$display" APPIMAGE_EXTRACT_AND_RUN=1 ELECTRON_OZONE_PLATFORM_HINT=x11 \
  "$CLIENT_APP" --no-sandbox --password-store=basic --disable-dev-shm-usage

sleep 3
for name in "${RUNTIME_NAMES[@]}"; do
  pid=$(pid_from_file "$name" 2>/dev/null || true)
  process_matches "$name" "$pid" || { echo "$name 启动失败，请查看 logs/$name.log"; exit 1; }
done

failed=0
trap - EXIT INT TERM
echo "HSLL Linux 客户端投影启动成功。"
echo "访问地址: http://服务器公网IP:$WEB_PORT/vnc.html?autoconnect=1&resize=scale&path=websockify"
echo "浏览器连接时请输入安装或 set-password.sh 设置的 VNC 密码。"
