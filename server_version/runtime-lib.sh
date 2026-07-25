#!/usr/bin/env bash

RUNTIME_NAMES=(client openbox novnc x11vnc xvfb)
CLEANUP_NAMES=(client openbox novnc x11vnc xvfb)

load_config() {
  local config_file="$BASE_DIR/config.env"
  [[ -f "$config_file" && ! -L "$config_file" ]] || {
    echo "配置文件不存在或是符号链接: $config_file" >&2
    echo "请先执行 sudo bash install.sh，或复制 config.example.env 为 config.env。" >&2
    return 1
  }
  # config.env is an administrator-owned shell configuration file.
  # shellcheck disable=SC1090
  source "$config_file"
  WEB_HOST=${WEB_HOST:-0.0.0.0}
  WEB_PORT=${WEB_PORT:-8787}
  SCREEN_WIDTH=${SCREEN_WIDTH:-1280}
  SCREEN_HEIGHT=${SCREEN_HEIGHT:-900}
  [[ "$WEB_HOST" =~ ^[A-Za-z0-9:._-]+$ ]] || { echo "WEB_HOST 格式无效。" >&2; return 1; }
  for value in WEB_PORT SCREEN_WIDTH SCREEN_HEIGHT; do
    [[ "${!value}" =~ ^[1-9][0-9]*$ ]] || { echo "$value 必须是正整数。" >&2; return 1; }
  done
  ((WEB_PORT <= 65535)) || { echo "WEB_PORT 必须不大于 65535。" >&2; return 1; }
  ((SCREEN_WIDTH >= 800 && SCREEN_WIDTH <= 7680)) || { echo "SCREEN_WIDTH 必须在 800~7680 之间。" >&2; return 1; }
  ((SCREEN_HEIGHT >= 600 && SCREEN_HEIGHT <= 4320)) || { echo "SCREEN_HEIGHT 必须在 600~4320 之间。" >&2; return 1; }
}

acquire_lifecycle_lock_for_shutdown() {
  if flock -w 7 9; then return 0; fi
  echo "无法在 7 秒内获取生命周期锁；请确认没有另一个启动、停止、更新或卸载操作正在执行。" >&2
  return 1
}

valid_pid() {
  [[ "${1:-}" =~ ^[1-9][0-9]*$ ]] && [[ -d "/proc/$1" ]]
}

process_matches() {
  local name="$1" pid="$2" cmd cwd environment project_marker=0
  valid_pid "$pid" || return 1
  cmd=$({ tr '\0' ' ' < "/proc/$pid/cmdline"; } 2>/dev/null || true)
  cwd=$(readlink -f "/proc/$pid/cwd" 2>/dev/null || true)
  environment=$({ tr '\0' '\n' < "/proc/$pid/environ"; } 2>/dev/null || true)
  if [[ "$cwd" == "$BASE_DIR" ]]; then
    project_marker=1
  elif [[ "$environment" == *"HSLL_PROJECT_ROOT=$BASE_DIR"* || "$environment" == *"HOME=$BASE_DIR/data/home"* ]]; then
    project_marker=1
  fi
  [[ "$project_marker" -eq 1 ]] || return 1

  case "$name" in
    client)
      [[ "$environment" == *"HSLL_COMPONENT=client"* ]] || return 1
      ;;
    novnc) [[ "$cmd" == *"websockify"* ]] ;;
    x11vnc) [[ "$cmd" == *"x11vnc"* ]] ;;
    xvfb) [[ "$cmd" == *"Xvfb :"* ]] ;;
    openbox) [[ "$cmd" == *"openbox"* ]] ;;
    *) return 1 ;;
  esac
}

pid_file_name() {
  printf '%s\n' "$1"
}

pid_from_file() {
  local file="$BASE_DIR/.runtime/$(pid_file_name "$1").pid"
  [[ -f "$file" && -r "$file" ]] || return 1
  { tr -d '[:space:]' < "$file"; } 2>/dev/null
}

find_project_pids() {
  local name="$1" proc pid
  for proc in /proc/[0-9]*; do
    pid=${proc##*/}
    if process_matches "$name" "$pid"; then printf '%s\n' "$pid"; fi
  done
}

terminate_process() {
  local name="$1" pid="$2" pgid attempts
  process_matches "$name" "$pid" || return 0
  pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d '[:space:]' || true)
  if [[ "$pgid" == "$pid" ]]; then kill -TERM -- "-$pid" 2>/dev/null || true; else kill -TERM "$pid" 2>/dev/null || true; fi
  for attempts in {1..50}; do
    process_matches "$name" "$pid" || return 0
    sleep 0.2
  done
  echo "$name (PID $pid) 未在 10 秒内退出，强制停止。"
  if [[ "$pgid" == "$pid" ]]; then kill -KILL -- "-$pid" 2>/dev/null || true; else kill -KILL "$pid" 2>/dev/null || true; fi
  for attempts in {1..10}; do
    process_matches "$name" "$pid" || return 0
    sleep 0.1
  done
  echo "无法停止 $name (PID $pid)。" >&2
  return 1
}

cleanup_runtime() {
  local name pid found failed=0 display number xvfb_pid lock_pid
  display=$({ tr -d '[:space:]' < "$BASE_DIR/.runtime/display"; } 2>/dev/null || true)
  xvfb_pid=$(pid_from_file xvfb 2>/dev/null || true)
  for name in "${CLEANUP_NAMES[@]}"; do
    pid=$(pid_from_file "$name" 2>/dev/null || true)
    if [[ -n "$pid" ]]; then
      if process_matches "$name" "$pid"; then terminate_process "$name" "$pid" || failed=1
      elif valid_pid "$pid"; then echo "忽略 $name 的失效 PID 文件（PID $pid 已被其他进程复用）。"
      fi
    fi
    rm -f -- "$BASE_DIR/.runtime/$(pid_file_name "$name").pid"
  done
  for name in "${CLEANUP_NAMES[@]}"; do
    while IFS= read -r found; do
      [[ -n "$found" ]] || continue
      echo "清理缺少 PID 文件的项目残留进程: $name (PID $found)"
      terminate_process "$name" "$found" || failed=1
    done < <(find_project_pids "$name")
  done
  if [[ "$display" =~ ^:([0-9]+)$ && "$xvfb_pid" =~ ^[1-9][0-9]*$ && ! -d "/proc/$xvfb_pid" ]]; then
    number="${BASH_REMATCH[1]}"
    lock_pid=$({ tr -cd '0-9' < "/tmp/.X${number}-lock"; } 2>/dev/null || true)
    if [[ "$lock_pid" == "$xvfb_pid" ]]; then
      rm -f -- "/tmp/.X${number}-lock" "/tmp/.X11-unix/X${number}"
    fi
  fi
  rm -f -- "$BASE_DIR/.runtime/display"
  return "$failed"
}

ensure_local_dir() {
  local dir="$1"
  [[ "$dir" == "$BASE_DIR"/* ]] || { echo "拒绝使用项目目录外路径: $dir" >&2; return 1; }
  [[ ! -L "$dir" ]] || { echo "拒绝使用符号链接目录: $dir" >&2; return 1; }
  mkdir -p -- "$dir"
  [[ "$(readlink -f "$dir")" == "$dir" ]] || { echo "目录通过符号链接指向了其他位置: $dir" >&2; return 1; }
  [[ -r "$dir" && -w "$dir" && -x "$dir" ]] || {
    echo "项目运行目录不可读写: $dir" >&2
    echo "如果之前曾用 sudo 启动，请修复项目内 data、logs、app 和 .runtime 的所有权。" >&2
    return 1
  }
}

ensure_runtime_tree() {
  local file
  umask 077
  ensure_local_dir "$BASE_DIR/.runtime"
  ensure_local_dir "$BASE_DIR/logs"
  ensure_local_dir "$BASE_DIR/data"
  ensure_local_dir "$BASE_DIR/data/home"
  ensure_local_dir "$BASE_DIR/data/tmp"
  ensure_local_dir "$BASE_DIR/data/xdg-config"
  ensure_local_dir "$BASE_DIR/data/xdg-cache"
  ensure_local_dir "$BASE_DIR/data/xdg-state"
  ensure_local_dir "$BASE_DIR/app"
  for file in xvfb.log openbox.log x11vnc.log novnc.log client.log; do
    [[ ! -L "$BASE_DIR/logs/$file" ]] || { echo "拒绝写入符号链接日志: logs/$file" >&2; return 1; }
  done
}

cleanup_transient_files() {
  find "$BASE_DIR/data/tmp" -mindepth 1 -maxdepth 1 -xdev -delete 2>/dev/null || true
  find "$BASE_DIR/app" -maxdepth 1 -type f -name '.client.AppImage.tmp-*' -delete 2>/dev/null || true
}

prepare_log() {
  local file="$BASE_DIR/logs/$1" size=0
  [[ ! -L "$file" ]] || { echo "拒绝写入符号链接日志: $file" >&2; return 1; }
  [[ ! -f "$file" ]] || size=$(wc -c < "$file")
  if ((size >= 10 * 1024 * 1024)); then
    rm -f -- "$file.1"
    mv -- "$file" "$file.1"
  fi
  touch -- "$file"
}

port_in_use() {
  ss -ltnH "sport = :$1" 2>/dev/null | grep -q .
}

wait_for_port() {
  local port="$1" attempts
  for attempts in {1..150}; do
    port_in_use "$port" && return 0
    sleep 0.2
  done
  return 1
}

is_linux_appimage() {
  local file="$1" header
  [[ -f "$file" && ! -L "$file" ]] || return 1
  # AppImage starts with ELF and carries the AI type marker at byte offsets 8..10.
  header=$(od -An -tx1 -N11 -- "$file" 2>/dev/null | tr -d '[:space:]')
  [[ "$header" =~ ^7f454c46[0-9a-f]{8}41490[12]$ ]]
}
