#!/usr/bin/env bash
set -Eeuo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$BASE_DIR"
# shellcheck disable=SC1091
source "$BASE_DIR/runtime-lib.sh"

found_problem=0
for name in "${RUNTIME_NAMES[@]}"; do
  pid=$(pid_from_file "$name" 2>/dev/null || true)
  if [[ -n "$pid" ]] && process_matches "$name" "$pid"; then
    echo "$name: 运行中 (PID $pid)"
  elif [[ -n "$pid" ]] && valid_pid "$pid"; then
    echo "$name: PID 文件已失效（PID $pid 属于其他进程）"
    found_problem=1
  else
    orphans=$(find_project_pids "$name" | paste -sd, -)
    if [[ -n "$orphans" ]]; then
      echo "$name: 存在无 PID 文件的项目残留进程 ($orphans)"
      found_problem=1
    else
      echo "$name: 未运行"
    fi
  fi
done

if [[ -f "$BASE_DIR/config.env" ]]; then
  load_config
  echo "访问地址: http://服务器公网IP:$WEB_PORT/vnc.html?autoconnect=1&resize=scale&path=websockify"
fi
exit "$found_problem"
