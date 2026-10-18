# shellcheck shell=bash
# vm.sh - container lifecycle (podman), status, logs.

vm_exists() {
  podman container exists "$(vm_name)" >/dev/null 2>&1
}

vm_state() {
  podman inspect --format '{{.State.Status}}' "$(vm_name)" 2>/dev/null || printf 'absent'
}

vm_ensure_image() {
  if podman image exists "$IMAGE"; then
    debug "image present: $IMAGE"
    return 0
  fi
  step "pulling image $IMAGE"
  podman pull "$IMAGE"
}

vm_create() {
  local name tun_dev=()
  name=$(vm_name)

  if [ -e /dev/net/tun ]; then
    tun_dev=(--device /dev/net/tun)
  else
    warn "/dev/net/tun missing - the VM will not have networking"
  fi

  step "creating container $name ($WINDOWS_VERSION, ${VM_CPUS}C/${VM_RAM}/${VM_DISK})"

  podman run -d \
    --name "$name" \
    --device /dev/kvm \
    "${tun_dev[@]}" \
    --cap-add NET_ADMIN \
    --security-opt label=disable \
    -e "VERSION=$WINDOWS_VERSION" \
    -e "DISK_SIZE=$VM_DISK" \
    -e "RAM_SIZE=$VM_RAM" \
    -e "CPU_CORES=$VM_CPUS" \
    -e "USERNAME=$VM_USER" \
    -e "PASSWORD=$WINDOWS_PASSWORD" \
    -e "LANGUAGE=Chinese" \
    -e "REGION=zh-CN" \
    -e "KEYBOARD=zh-CN" \
    -e "TZ=${TZ:-Asia/Shanghai}" \
    -e "ARGUMENTS=$VM_ARGUMENTS" \
    -p "127.0.0.1:${RDP_PORT}:3389/tcp" \
    -p "127.0.0.1:${CONSOLE_PORT}:8006" \
    -v "$STORAGE:/storage" \
    -v "$OEM:/oem" \
    -v "$SHARED:/shared" \
    --stop-timeout 120 \
    "$IMAGE" >/dev/null

  write_state "created_at" "$(date -Iseconds)"
  write_state "image" "$IMAGE"
  write_state "windows_version" "$WINDOWS_VERSION"
}

vm_start() {
  if ! vm_exists; then
    die "container $(vm_name) does not exist - run 'porthole provision' first"
  fi
  local state
  state=$(vm_state)
  case $state in
    running) return 0 ;;
    paused) info "resuming paused VM"; podman unpause "$(vm_name)" >/dev/null ;;
    exited|created) info "starting VM"; podman start "$(vm_name)" >/dev/null ;;
    *) die "unexpected container state: $state" ;;
  esac
}

vm_pause() {
  if ! vm_exists; then
    return 0
  fi
  if [ "$(vm_state)" = "running" ]; then
    podman pause "$(vm_name)" >/dev/null 2>&1 || warn "could not pause the VM"
    info "VM paused (CPU released, memory kept)"
  fi
}

vm_resume() {
  if vm_exists && [ "$(vm_state)" = "paused" ]; then
    podman unpause "$(vm_name)" >/dev/null
    info "VM resumed"
  fi
}

vm_stop() {
  if ! vm_exists; then
    return 0
  fi
  local state
  state=$(vm_state)
  if [ "$state" = "paused" ]; then
    podman unpause "$(vm_name)" >/dev/null 2>&1 || true
  fi
  if [ "$state" != "exited" ]; then
    step "shutting the VM down (up to 120s)"
    podman stop --time 120 "$(vm_name)" >/dev/null 2>&1 || podman kill "$(vm_name)" >/dev/null 2>&1 || true
  fi
}

vm_remove() {
  if vm_exists; then
    podman rm -f "$(vm_name)" >/dev/null 2>&1 || true
  fi
}

vm_ensure_running() {
  if ! vm_exists; then
    die "no VM for profile '$PROFILE' yet - run 'porthole provision' first"
  fi
  vm_start
  local state
  state=$(vm_state)
  [ "$state" = "running" ] || die "VM is '$state', expected 'running'"
}

cmd_up() {
  require_runtime
  ensure_dirs
  load_secret
  vm_ensure_image
  vm_ensure_running
  info "VM running; RDP on 127.0.0.1:$RDP_PORT"
}

cmd_down() {
  load_secret || true
  vm_stop
  info "VM stopped"
}

cmd_pause() {
  vm_pause
}

cmd_resume() {
  vm_resume
}

cmd_logs() {
  local follow=0 tail=200
  while [ $# -gt 0 ]; do
    case $1 in
      -f|--follow) follow=1; shift ;;
      -n|--lines) tail=$2; shift 2 ;;
      *) die "logs: unknown argument: $1" ;;
    esac
  done
  vm_exists || die "no container for profile '$PROFILE'"
  if [ "$follow" -eq 1 ]; then
    podman logs -f --tail "$tail" "$(vm_name)"
  else
    podman logs --tail "$tail" "$(vm_name)"
  fi
}

cmd_reset() {
  local all=0 yes=0
  while [ $# -gt 0 ]; do
    case $1 in
      -y|--yes) yes=1; shift ;;
      --all) all=1; shift ;;
      *) die "reset: unknown argument: $1" ;;
    esac
  done
  if [ "$yes" -eq 0 ]; then
    printf 'This removes the container for profile %s' "$PROFILE"
    [ "$all" -eq 1 ] && printf ' AND all VM data under %s' "$DATA"
    printf '.\n'
    die "refusing to reset without --yes"
  fi
  vm_stop
  vm_remove
  if [ "$all" -eq 1 ]; then
    rm -rf "$DATA"
    info "removed $DATA"
  fi
  info "reset done"
}

cmd_status() {
  local state="absent" rdp="closed" disk="-"
  vm_exists && state=$(vm_state)

  if rdp_probe 4; then
    rdp="handshake ok"
  elif tcp_open 127.0.0.1 "$RDP_PORT"; then
    rdp="port open, no answer yet"
  fi
  if [ -d "$STORAGE" ]; then
    disk=$(du -sh "$STORAGE" 2>/dev/null | cut -f1)
  fi

  printf 'profile      %s  (%s)\n' "$PROFILE_ID" "$PROFILE_FILE"
  printf 'image        %s\n' "$IMAGE"
  printf 'windows      %s  (%s vCPU / %s RAM / %s disk)\n' \
    "$WINDOWS_VERSION" "$VM_CPUS" "$VM_RAM" "$VM_DISK"
  printf 'container    %s  [%s]\n' "$(vm_name)" "$state"
  printf 'rdp          127.0.0.1:%s  [%s]\n' "$RDP_PORT" "$rdp"
  printf 'console      http://127.0.0.1:%s/\n' "$CONSOLE_PORT"
  printf 'data         %s  (on disk: %s)\n' "$DATA" "$disk"

  if [ -f "$STATUS_FILE" ]; then
    printf 'provision    %s\n' "$(json_get "$STATUS_FILE" stage 2>/dev/null || printf 'unknown')"
  elif [ -f "$STORAGE/custom.iso" ]; then
    printf 'provision    iso ready, Windows not installed yet\n'
  else
    printf 'provision    not started  (run: porthole provision)\n'
  fi
}

cmd_config() {
  local what=${1:-show}
  case $what in
    path) printf '%s\n' "$PROFILE_FILE" ;;
    show)
      printf '# profile   %s\n' "$PROFILE_FILE"
      printf '# image     %s\n' "$IMAGE"
      printf 'vm.version        = %s\n' "$WINDOWS_VERSION"
      printf 'vm.cpus           = %s\n' "$VM_CPUS"
      printf 'vm.ram            = %s\n' "$VM_RAM"
      printf 'vm.disk           = %s\n' "$VM_DISK"
      printf 'vm.username       = %s\n' "$VM_USER"
      printf 'vm.rdp_port       = %s\n' "$RDP_PORT"
      printf 'session.mode      = %s\n' "$SESSION_MODE"
      printf 'session.dpi_scale = %s\n' "$DPI_SCALE"
      printf 'rdp.security      = %s\n' "$RDP_SECURITY"
      printf 'lifecycle.pause   = %s\n' "$PAUSE_ON_CLOSE"
      printf 'data              = %s\n' "$DATA"
      ;;
    *) die "config: expected 'show' or 'path'" ;;
  esac
}
