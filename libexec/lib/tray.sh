# shellcheck shell=bash
# tray.sh - StatusNotifierItem icon in the GNOME top bar.

tray_pidfile() {
  printf '%s/porthole-%s/tray.pid' "${XDG_RUNTIME_DIR:-/tmp}" "$(id -u)"
}

tray_running() {
  local pidfile pid
  pidfile=$(tray_pidfile)
  [ -f "$pidfile" ] || return 1
  pid=$(cat "$pidfile" 2>/dev/null || true)
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

ensure_tray() {
  tray_running && return 0
  local script="$PORTHOLE_ROOT/libexec/porthole-tray.py"
  [ -f "$script" ] || return 0
  mkdir -p "$(dirname "$(tray_pidfile)")" 2>/dev/null || true
  setsid nohup python3 "$script" >/dev/null 2>&1 &
  sleep 0.2
  return 0
}

cmd_tray() {
  local script="$PORTHOLE_ROOT/libexec/porthole-tray.py"
  [ -f "$script" ] || die "tray helper missing: $script"
  have python3 || die "python3 not found"
  mkdir -p "$(dirname "$(tray_pidfile)")" 2>/dev/null || true
  printf '%s\n' "$$" >"$(tray_pidfile)"
  trap 'rm -f "$(tray_pidfile)"' EXIT
  exec python3 "$script"
}
