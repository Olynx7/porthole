# shellcheck shell=bash
# doctor.sh - collect everything needed to debug a broken setup.

doctor_report() {
  local out=$1
  {
    printf 'porthole %s\n' "$PORTHOLE_VERSION"
    printf 'generated %s\n' "$(date -Iseconds)"
    printf 'host      %s\n' "$(uname -srm)"
    printf 'session   %s / %s\n' "${XDG_SESSION_TYPE:-unknown}" "${XDG_CURRENT_DESKTOP:-unknown}"
    printf 'display   %s\n' "${DISPLAY:-none}"
    printf '\n[config]\n'
    printf 'profile      %s\n' "$PROFILE_FILE"
    printf 'image        %s\n' "$IMAGE"
    printf 'windows      %s (%s vCPU / %s RAM / %s disk)\n' \
      "$WINDOWS_VERSION" "$VM_CPUS" "$VM_RAM" "$VM_DISK"
    printf 'session      mode=%s grab_keyboard=%s floatbar=%s dpi=%s\n' \
      "$SESSION_MODE" "$GRAB_KEYBOARD" "$FLOATBAR" "$DPI_SCALE"
    printf 'rdp          port=%s security=%s\n' "$RDP_PORT" "$RDP_SECURITY"
    printf '\n[tooling]\n'
    printf 'podman       %s\n' "$(podman --version 2>/dev/null || echo missing)"
    printf 'xfreerdp     %s\n' "$(xfreerdp /version 2>/dev/null | head -1 || echo missing)"
    printf 'python3      %s\n' "$(python3 --version 2>/dev/null || echo missing)"
    printf 'kvm          %s\n' "$([ -e /dev/kvm ] && echo present || echo missing)"
    printf '\n[container]\n'
    podman ps -a --filter "name=$(vm_name)" \
      --format '{{.Names}} {{.Status}} {{.Image}}' 2>/dev/null || true
    printf '\n[ports]\n'
    if tcp_open 127.0.0.1 "$RDP_PORT"; then printf 'rdp 3391     open\n'; else printf 'rdp 3391     closed\n'; fi
    printf '\n[files]\n'
    ls -lh "$STORAGE/custom.iso" 2>/dev/null || printf 'iso          missing\n'
    du -sh "$STORAGE" 2>/dev/null || true
    printf '\n[provisioning]\n'
    cat "$STATUS_FILE" 2>/dev/null || printf 'no status file\n'
    printf '\n[container log tail]\n'
    podman logs --tail 120 "$(vm_name)" 2>&1 || true
  } >"$out"
}

cmd_doctor() {
  local bundle=0
  while [ $# -gt 0 ]; do
    case $1 in
      -b|--bundle) bundle=1; shift ;;
      *) die "doctor: unknown argument: $1" ;;
    esac
  done

  mkdir -p "$STATE_DIR"
  local stamp out
  stamp=$(date +%Y%m%d-%H%M%S)
  out="$STATE_DIR/doctor-$stamp.txt"
  doctor_report "$out"
  info "report: $out"

  if [ "$bundle" -eq 1 ]; then
    local dir tar
    dir=$(mktemp -d "${TMPDIR:-/tmp}/porthole-doctor.XXXXXX")
    cp -- "$out" "$dir/report.txt"
    cp -- "$PROFILE_FILE" "$dir/profile.toml" 2>/dev/null || true
    cp -- "$STATUS_FILE" "$dir/status.json" 2>/dev/null || true
    if [ -d "$OEM" ]; then
      cp -r -- "$OEM" "$dir/oem" 2>/dev/null || true
    fi
    tar="$STATE_DIR/doctor-$stamp.tar.gz"
    tar -czf "$tar" -C "$(dirname "$dir")" "$(basename "$dir")" 2>/dev/null
    rm -rf "$dir"
    info "bundle: $tar"
  fi
}
