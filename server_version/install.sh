#!/usr/bin/env bash
set -Eeuo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$BASE_DIR"

if [[ ${EUID} -ne 0 ]]; then
  echo "请执行: sudo bash install.sh"
  exit 1
fi
if [[ $# -ne 0 ]]; then
  echo "用法: sudo bash install.sh"
  exit 2
fi

# shellcheck disable=SC1091
source "$BASE_DIR/runtime-lib.sh"
ensure_runtime_tree
exec 9>"$BASE_DIR/.runtime/lifecycle.lock"
flock 9
cleanup_runtime
cleanup_transient_files

echo "[1/3] 安装图形投影运行依赖"
export DEBIAN_FRONTEND=noninteractive
apt-get update

# Ubuntu 24.04 renamed several libraries during the 64-bit time_t
# transition. Most old names are resolved automatically by apt, but
# libasound2 became an ambiguous virtual package, so select its concrete
# package name explicitly while retaining compatibility with older Ubuntu.
if apt-cache show libasound2t64 >/dev/null 2>&1; then
  ALSA_PACKAGE=libasound2t64
else
  ALSA_PACKAGE=libasound2
fi

apt-get install -y \
  xvfb openbox x11vnc novnc websockify util-linux procps iproute2 openssl \
  libgtk-3-0 libnss3 libgbm1 "$ALSA_PACKAGE" libxss1 libxtst6 \
  libatk-bridge2.0-0 libdrm2 fonts-noto-cjk

echo "[2/3] 初始化项目配置和 VNC 密码"
[[ ! -L "$BASE_DIR/config.env" ]] || { echo "拒绝使用符号链接配置: config.env"; exit 1; }
[[ ! -L "$BASE_DIR/data/vnc.pass" ]] || { echo "拒绝使用符号链接密码文件: data/vnc.pass"; exit 1; }
if [[ ! -f "$BASE_DIR/config.env" ]]; then
  cp -- "$BASE_DIR/config.example.env" "$BASE_DIR/config.env"
fi

generated_password=''
if [[ ! -f "$BASE_DIR/data/vnc.pass" ]]; then
  generated_password=$(openssl rand -hex 4)
  x11vnc -storepasswd "$generated_password" "$BASE_DIR/data/vnc.pass" >/dev/null
fi

echo "[3/3] 清理已删除的旧服务器依赖"
rm -rf -- "$BASE_DIR/node_modules" "$BASE_DIR/data/npm-cache" "$BASE_DIR/data/browser-profile"
chmod +x \
  "$BASE_DIR/install.sh" "$BASE_DIR/start.sh" "$BASE_DIR/stop.sh" \
  "$BASE_DIR/status.sh" "$BASE_DIR/uninstall.sh" \
  "$BASE_DIR/update-client.sh" "$BASE_DIR/set-password.sh" "$BASE_DIR/check.sh"
chmod 600 "$BASE_DIR/config.env" "$BASE_DIR/data/vnc.pass"

OWNER=${SUDO_USER:-root}
if [[ "$OWNER" != root ]]; then
  OWNER_GROUP=$(id -gn "$OWNER")
  chown -R "$OWNER":"$OWNER_GROUP" \
    "$BASE_DIR/app" "$BASE_DIR/data" "$BASE_DIR/logs" "$BASE_DIR/.runtime" "$BASE_DIR/config.env"
fi

echo
echo "安装完成。"
if [[ -n "$generated_password" ]]; then
  echo "本次生成的 VNC 密码: $generated_password"
  echo "请立即保存；之后可运行 bash set-password.sh 修改。"
else
  echo "已保留现有 VNC 密码。"
fi
if is_linux_appimage "$BASE_DIR/app/client.AppImage"; then
  echo "启动: bash start.sh"
else
  echo "下一步先安装 Linux 客户端:"
  echo "  bash update-client.sh /path/to/hsll-order-reminder-v1.1.0.AppImage"
fi
