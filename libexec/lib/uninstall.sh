# shellcheck shell=bash
# uninstall.sh - remove porthole from this host.

cmd_uninstall() {
  local purge=0 yes=0
  while [ $# -gt 0 ]; do
    case $1 in
      -p|--purge) purge=1; shift ;;
      -y|--yes) yes=1; shift ;;
      *) die "uninstall: unknown argument: $1" ;;
    esac
  done

  if [ "$yes" -eq 0 ]; then
    printf 'This removes the porthole code from %s\n' "${PORTHOLE_INSTALL_ROOT:-$HOME/.local/lib/porthole}"
    [ "$purge" -eq 1 ] && printf 'and ALL VM data under %s\n' "$DATA_ROOT"
    die "refusing to uninstall without --yes"
  fi

  vm_stop
  vm_remove

  local install_root=${PORTHOLE_INSTALL_ROOT:-$HOME/.local/lib/porthole}
  local data_home=${XDG_DATA_HOME:-$HOME/.local/share}

  rm -f "$HOME/.local/bin/porthole"
  rm -f "$data_home/applications/porthole-"*.desktop
  rm -f "$data_home/icons/hicolor"/*/apps/"$PROFILE_ICON".png 2>/dev/null || true
  rm -rf "$install_root"

  if [ "$purge" -eq 1 ]; then
    rm -rf "$DATA_ROOT"
    rm -rf "$CFG_DIR"
    rm -rf "$STATE_DIR"
    info "removed VM data, config and state"
  fi

  info "porthole uninstalled"
}
