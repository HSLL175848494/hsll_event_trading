#!/usr/bin/env bash
set -Eeuo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

scripts=(
  runtime-lib.sh install.sh start.sh stop.sh status.sh uninstall.sh
  update-client.sh set-password.sh check.sh
)
for script in "${scripts[@]}"; do
  bash -n "$BASE_DIR/$script"
done

for removed in src public test package.json config.example.json cleanup-old-install.sh; do
  [[ ! -e "$BASE_DIR/$removed" ]] || {
    echo "发现应删除的旧服务器文件: $removed" >&2
    exit 1
  }
done

grep -q 'app/client.AppImage' "$BASE_DIR/start.sh"
grep -q 'x11vnc' "$BASE_DIR/start.sh"
grep -q 'websockify' "$BASE_DIR/start.sh"
grep -q -- '--no-sandbox' "$BASE_DIR/start.sh"
grep -q 'apt-cache show libasound2t64' "$BASE_DIR/install.sh"
grep -q '"$ALSA_PACKAGE"' "$BASE_DIR/install.sh"
for script in install.sh start.sh stop.sh status.sh uninstall.sh update-client.sh set-password.sh; do
  if grep -n -E 'Playwright|src/index\.js|node src/|server_url|order-reminders|google-chrome' "$BASE_DIR/$script"; then
    echo "发现旧 Worker 业务逻辑引用: $script" >&2
    exit 1
  fi
done

echo "检查通过：项目只包含 Linux 客户端投影运行逻辑。"
