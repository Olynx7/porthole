# shellcheck shell=bash
# tray.sh - StatusNotifierItem icon in the GNOME top bar.

cmd_tray() {
  local script="$PORTHOLE_ROOT/libexec/porthole-tray.py"
  [ -f "$script" ] || die "tray helper missing: $script"
  have python3 || die "python3 not found"
  exec python3 "$script"
}
