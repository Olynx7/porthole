# shellcheck shell=bash
# common.sh - paths, logging, configuration access, small helpers.

info()  { printf '  %s\n' "$*"; }
step()  { printf '\n==> %s\n' "$*"; }

warn() {
  printf 'porthole: warning: %s\n' "$*" >&2
}

die() {
  printf 'porthole: error: %s\n' "$*" >&2
  exit 2
}

debug() {
  if [ "${PORTHOLE_DEBUG:-0}" = "1" ]; then
    printf 'porthole: debug: %s\n' "$*" >&2
  fi
  return 0
}

have() {
  command -v -- "$1" >/dev/null 2>&1
}

init_paths() {
  CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/porthole"

  # Optional host-level defaults. CLI flags still win over this file.
  local cli_profile="${PORTHOLE_PROFILE:-}"
  if [ -f "$CFG_DIR/porthole.conf" ]; then
    # shellcheck disable=SC1090
    . "$CFG_DIR/porthole.conf"
  fi
  PROFILE="${cli_profile:-${PORTHOLE_PROFILE:-wecom}}"

  DATA_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/porthole"
  STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/porthole"
  RUN_DIR="${XDG_RUNTIME_DIR:-/tmp}/porthole-$(id -u)"

  PROFILE_FILE="$CFG_DIR/profiles/$PROFILE.toml"
  if [ ! -f "$PROFILE_FILE" ]; then
    PROFILE_FILE="$PORTHOLE_ROOT/config/profiles/$PROFILE.toml"
  fi
  if [ ! -f "$PROFILE_FILE" ]; then
    local avail=""
    local f
    for f in "$PORTHOLE_ROOT"/config/profiles/*.toml; do
      [ -f "$f" ] || continue
      avail="$avail $(basename "$f" .toml)"
    done
    die "unknown profile '$PROFILE' (available:${avail:- none})"
  fi

  DATA="$DATA_ROOT/$PROFILE"
  STORAGE="$DATA/storage"
  SHARED="$DATA/shared"
  OEM="$DATA/oem"
  STATE_FILE="$DATA/state.json"
  SECRETS="$CFG_DIR/secrets/$PROFILE.env"
  STATUS_FILE="$SHARED/porthole-status.json"

  export PROFILE PROFILE_FILE CFG_DIR DATA_ROOT STATE_DIR RUN_DIR
  export DATA STORAGE SHARED OEM STATE_FILE SECRETS STATUS_FILE
}

cfg_init() {
  mkdir -p "$RUN_DIR"
  chmod 700 "$RUN_DIR" 2>/dev/null || true

  local cache="$RUN_DIR/cfg-$PROFILE.env"
  if ! python3 "$PORTHOLE_ROOT/tools/toml2env.py" "$PROFILE_FILE" >"$cache"; then
    die "cannot parse profile: $PROFILE_FILE"
  fi
  # shellcheck disable=SC1090
  . "$cache"

  PROFILE_ID=${CFG_PROFILE_ID:-$PROFILE}
  PROFILE_NAME=${CFG_PROFILE_NAME:-$PROFILE}
  PROFILE_ICON=${CFG_PROFILE_ICON:-$PROFILE}

  IMAGE=${CFG_VM_IMAGE:-ghcr.io/dockur/windows:latest}
  WINDOWS_VERSION=${CFG_VM_VERSION:-tiny10}
  VM_CPUS=${CFG_VM_CPUS:-2}
  VM_RAM=${CFG_VM_RAM:-4G}
  VM_DISK=${CFG_VM_DISK:-32G}
  VM_USER=${CFG_VM_USERNAME:-porthole}
  VM_ARGUMENTS=${CFG_VM_ARGUMENTS:-}
  RDP_PORT=${CFG_VM_RDP_PORT:-3391}
  CONSOLE_PORT=${CFG_VM_CONSOLE_PORT:-8006}

  SESSION_MODE=${CFG_SESSION_MODE:-fullscreen}
  GRAB_KEYBOARD=${CFG_SESSION_GRAB_KEYBOARD:-false}
  FLOATBAR=${CFG_SESSION_FLOATBAR:-true}
  DPI_SCALE=${CFG_SESSION_DPI_SCALE:-125}
  MONITORS=${CFG_SESSION_MONITORS:-}

  RDP_SECURITY=${CFG_RDP_SECURITY:-tls}
  PAUSE_ON_CLOSE=${CFG_LIFECYCLE_PAUSE_ON_CLOSE:-true}
  STOP_AFTER_IDLE=${CFG_LIFECYCLE_STOP_AFTER_IDLE_MIN:-0}

  APP_EXE=${CFG_APP_EXE:-}
  APP_INSTALLER=${CFG_APP_INSTALLER:-}
  APP_STARTUP=${CFG_APP_STARTUP:-true}

  export PROFILE_ID PROFILE_NAME PROFILE_ICON IMAGE WINDOWS_VERSION
  export VM_CPUS VM_RAM VM_DISK VM_USER VM_ARGUMENTS RDP_PORT CONSOLE_PORT
  export SESSION_MODE GRAB_KEYBOARD FLOATBAR DPI_SCALE MONITORS
  export RDP_SECURITY PAUSE_ON_CLOSE STOP_AFTER_IDLE
  export APP_EXE APP_INSTALLER APP_STARTUP
}

# cfg <section.key> [default]
cfg() {
  local key flat val
  key=$1
  flat="CFG_$(printf '%s' "$key" | tr '.-' '__' | tr '[:lower:]' '[:upper:]')"
  eval "val=\${$flat-}"
  if [ -n "${val-}" ]; then
    printf '%s' "$val"
  else
    printf '%s' "${2-}"
  fi
}

# cfg_bool -> success when the value is exactly "true"
cfg_bool() {
  [ "$(cfg "$1" "${2:-false}")" = "true" ]
}

# cfg_list <section.key> - prints one element per line
cfg_list() {
  local flat val
  flat="CFG_$(printf '%s' "$1" | tr '.-' '__' | tr '[:lower:]' '[:upper:]')"
  eval "val=\${$flat-}"
  [ -n "${val-}" ] || return 0
  printf '%s\n' "$val"
}

vm_name() {
  printf 'porthole-%s' "$PROFILE"
}

ensure_dirs() {
  mkdir -p "$DATA" "$STORAGE" "$SHARED" "$OEM" "$CFG_DIR/secrets" "$STATE_DIR"
  chmod 700 "$CFG_DIR" "$CFG_DIR/secrets" 2>/dev/null || true
}

require_runtime() {
  have podman || die "podman not found (needed for the Windows VM)"
  have python3 || die "python3 not found"
  if ! have xfreerdp; then
    warn "xfreerdp not found - 'porthole run' will fail (install freerdp)"
  fi
}

load_secret() {
  WINDOWS_PASSWORD=""
  if [ -f "$SECRETS" ]; then
    # shellcheck disable=SC1090
    . "$SECRETS"
  fi
  export WINDOWS_PASSWORD
}

gen_password() {
  python3 - <<'PY'
import secrets, string
alphabet = string.ascii_letters + string.digits
print(''.join(secrets.choice(alphabet) for _ in range(20)) + 'Aa1!')
PY
}

tcp_open() {
  local host=$1 port=$2
  (exec 3<>"/dev/tcp/$host/$port") 2>/dev/null || return 1
  exec 3>&-
  return 0
}

# wait_for_tcp host port timeout_seconds
wait_for_tcp() {
  local host=$1 port=$2 timeout=$3
  local waited=0
  while [ "$waited" -lt "$timeout" ]; do
    if tcp_open "$host" "$port"; then
      return 0
    fi
    sleep 2
    waited=$((waited + 2))
    debug "waiting for $host:$port (${waited}s/${timeout}s)"
  done
  return 1
}

json_get() {
  local file=$1 key=$2
  python3 - "$file" "$key" <<'PY'
import json, sys
path, key = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding='utf-8') as fh:
        data = json.load(fh)
except Exception:
    sys.exit(1)
cur = data
for part in key.split('.'):
    if not isinstance(cur, dict) or part not in cur:
        sys.exit(1)
    cur = cur[part]
print(cur if not isinstance(cur, bool) else str(cur).lower())
PY
}

write_state() {
  local key=$1 value=$2
  ensure_dirs
  python3 - "$STATE_FILE" "$key" "$value" <<'PY'
import json, os, sys
path, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
data = {}
if os.path.exists(path):
    try:
        with open(path, encoding='utf-8') as fh:
            data = json.load(fh)
    except Exception:
        data = {}
data[key] = value
tmp = path + '.tmp'
with open(tmp, 'w', encoding='utf-8') as fh:
    json.dump(data, fh, ensure_ascii=False, indent=2, sort_keys=True)
os.replace(tmp, path)
PY
}

human_size() {
  python3 -c 'import sys;n=float(sys.argv[1]);u=["B","KiB","MiB","GiB","TiB"];i=0
while n>=1024 and i<len(u)-1: n/=1024; i+=1
print(f"{n:.1f} {u[i]}")' "${1:-0}" 2>/dev/null || printf '%s\n' "${1:-0}"
}
