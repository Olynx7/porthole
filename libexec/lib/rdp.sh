# shellcheck shell=bash
# rdp.sh - the actual FreeRDP session.

instance_lock() {
  # Deliberately not flock(1): the lock file descriptor is inherited by every
  # child, and `podman start` hands it to conmon, which outlives the client -
  # the lock then looks busy forever. A directory with a pid file has no such
  # inheritance problem and can detect a stale owner.
  mkdir -p "$RUN_DIR"
  LOCK_DIR="$RUN_DIR/$PROFILE.session"

  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    local owner=""
    [ -f "$LOCK_DIR/pid" ] && owner=$(cat "$LOCK_DIR/pid" 2>/dev/null || true)
    if [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null; then
      die "another porthole session for '$PROFILE' is already running (pid $owner)"
    fi
    debug "removing stale session lock${owner:+ (owner $owner is gone)}"
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" || die "cannot create $LOCK_DIR"
  fi

  printf '%s\n' "$$" >"$LOCK_DIR/pid"
  trap 'rm -rf "$LOCK_DIR"' EXIT
}

x_screen_size() {
  python3 - <<'PY'
import ctypes

x11 = ctypes.CDLL("libX11.so.6")
x11.XOpenDisplay.restype = ctypes.c_void_p
x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
x11.XDisplayWidth.argtypes = [ctypes.c_void_p, ctypes.c_int]
x11.XDisplayHeight.argtypes = [ctypes.c_void_p, ctypes.c_int]

display = x11.XOpenDisplay(None)
if not display:
    raise SystemExit(1)
print(f"{x11.XDisplayWidth(display, 0)}x{x11.XDisplayHeight(display, 0)}")
PY
}

rdp_build_args() {
  local mode=$1 dpi=$2 grab=$3 floatbar=$4

  printf '/v:127.0.0.1:%s\n' "$RDP_PORT"
  printf '/u:%s\n' "$VM_USER"
  printf '/p:%s\n' "$WINDOWS_PASSWORD"
  printf '/cert:ignore\n'
  printf '/sec:%s\n' "$RDP_SECURITY"
  printf '/sound\n'
  printf '/clipboard\n'
  printf '/drive:shared,%s\n' "$SHARED"
  if [ "$(cfg session.disable_win_key true)" = "true" ]; then
    # The Windows key gets swallowed by the compositor on the way back, which
    # leaves the guest convinced that Win is still held down. Remap it to
    # "no key" on the client side so it never reaches the session at all.
    printf '/kbd:lang:0x804,remap:0x5b=0x00,remap:0x5c=0x00\n'
  else
    printf '/kbd:lang:0x804\n'
  fi
  printf '/log-level:WARN\n'

  local smart="false"
  if [ "$mode" = "fullscreen" ] && [ "$(cfg session.smart_sizing true)" = "true" ]; then
    smart="true"
  fi

  # FreeRDP refuses to combine these two: smart sizing needs a fixed session
  # size to scale, dynamic resolution changes it on the fly.
  if [ "$smart" = "false" ]; then
    printf '+dynamic-resolution\n'
  fi

  if [ "$mode" = "fullscreen" ]; then
    printf '/f\n'
    printf '/wm-class:porthole\n'
    # The guest cannot always switch to the X screen size (the virtual display
    # has a maximum resolution), so scale the remote image to fit instead of
    # leaving black borders around a small desktop.
    if [ "$smart" = "true" ]; then
      local screen
      screen=$(x_screen_size 2>/dev/null || true)
      if [ -n "$screen" ]; then
        printf '/smart-sizing:%s\n' "$screen"
      fi
    fi
    if [ "$floatbar" = "true" ]; then
      printf '/floatbar:sticky:off,default:hidden,show:fullscreen\n'
    fi
  else
    local window_size
    window_size=$(cfg session.window_size auto)
    if [ "$window_size" = "auto" ]; then
      window_size=$(x_screen_size 2>/dev/null || printf '1600x900')
    fi
    printf '/size:%s\n' "$window_size"
    printf -- '-decorations\n'
    printf '/wm-class:porthole\n'
  fi

  if [ "$grab" = "true" ]; then
    printf '/grab-keyboard\n'
  else
    printf -- '-grab-keyboard\n'
  fi

  if [ -n "$MONITORS" ]; then
    printf '/monitors:%s\n' "$MONITORS"
  fi

  if [ -n "${RDP_SCALE_OVERRIDE:-}" ] && [ "$RDP_SCALE_OVERRIDE" != "0" ]; then
    printf '/scale:%s\n' "$RDP_SCALE_OVERRIDE"
  fi

  local extra
  while IFS= read -r extra; do
    [ -n "$extra" ] || continue
    case $extra in
      /network:*|*/network:*)
        die "refusing to pass '$extra': /network: has reset the server before"
        ;;
    esac
    printf '%s\n' "$extra"
  done < <(cfg_list session.extra_args)
}

rdp_connect() {
  local mode=$1
  local grab=$GRAB_KEYBOARD floatbar=$FLOATBAR

  [ "$mode" = "fullscreen" ] && [ "$SESSION_MODE" = "window" ] && mode="window"

  local args_file
  args_file=$(mktemp "${TMPDIR:-/tmp}/porthole-args.XXXXXX")
  chmod 600 "$args_file"
  rdp_build_args "$mode" "$DPI_SCALE" "$grab" "$floatbar" >"$args_file"
  debug "xfreerdp args: $(tr '\n' ' ' <"$args_file" | sed 's#/p:[^ ]*#/p:***#')"

  local rc=0
  if ! xfreerdp "/args-from:file:$args_file"; then
    rc=$?
  fi
  rm -f "$args_file"

  if [ "$rc" -ne 0 ]; then
    warn "xfreerdp exited with code $rc"
  fi
  return "$rc"
}

rdp_probe() {
  # A TCP connect is meaningless here: rootless podman listens on the host port
  # long before the guest has an RDP listener. Send a real X.224 connection
  # request and require a Connection Confirm (0xd0) back.
  python3 - "$RDP_PORT" "${1:-0}" <<'PY'
import socket
import sys
import time

port = int(sys.argv[1])
timeout = float(sys.argv[2])
request = bytes.fromhex("030000130ee000000000000100080003000000")
deadline = time.time() + timeout

while True:
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=3) as sock:
            sock.sendall(request)
            data = sock.recv(64)
        if len(data) >= 6 and data[0] == 0x03 and data[5] == 0xD0:
            sys.exit(0)
    except OSError:
        pass
    if time.time() >= deadline:
        sys.exit(1)
    time.sleep(2)
PY
}

cmd_run() {
  local mode="fullscreen"
  while [ $# -gt 0 ]; do
    case $1 in
      --windowed) mode="window"; shift ;;
      --grab-keyboard) GRAB_KEYBOARD=true; shift ;;
      --dpi) [ $# -ge 2 ] || die "--dpi needs a value"; DPI_SCALE=$2; export DPI_SCALE; shift 2 ;;
      *) die "run: unknown argument: $1" ;;
    esac
  done

  require_runtime
  have xfreerdp || die "xfreerdp not found (dnf install freerdp)"
  load_secret
  [ -n "${WINDOWS_PASSWORD:-}" ] || die "no Windows password - run 'porthole provision' first"

  instance_lock
  vm_ensure_running

  step "waiting for the RDP service on 127.0.0.1:$RDP_PORT"
  if ! rdp_probe 300; then
    die "RDP did not answer - see 'porthole logs' or http://127.0.0.1:$CONSOLE_PORT/"
  fi

  if [ ! -f "$STATUS_FILE" ]; then
    warn "provisioning has not reported completion yet - the session may show a setup screen"
  fi

  step "connecting"
  local rc=0
  rdp_connect "$mode" || rc=$?

  if [ "${PAUSE_ON_CLOSE:-true}" = "true" ]; then
    vm_pause
  fi

  if [ "$rc" -ne 0 ]; then
    exit 4
  fi
}

cmd_shell() {
  require_runtime
  have xfreerdp || die "xfreerdp not found (dnf install freerdp)"
  load_secret
  [ -n "${WINDOWS_PASSWORD:-}" ] || die "no Windows password - run 'porthole provision' first"
  vm_ensure_running
  rdp_probe 300 || die "RDP did not answer"
  step "opening a debug desktop session"
  local rc=0
  rdp_connect "window" || rc=$?
  [ "$rc" -ne 0 ] && exit 4
  return 0
}
