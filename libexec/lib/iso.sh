# shellcheck shell=bash
# iso.sh - pinned ISO pre-download, verification and import.

iso_file() {
  printf '%s/custom.iso' "$STORAGE"
}

iso_meta() {
  python3 - "$PORTHOLE_ROOT/tools/iso.lock" "$WINDOWS_VERSION" "$1" <<'PY'
import sys
import tomllib

path, version, key = sys.argv[1:4]
try:
    with open(path, "rb") as fh:
        data = tomllib.load(fh)
except OSError:
    sys.exit(1)
entry = data.get(version)
if not isinstance(entry, dict) or key not in entry:
    sys.exit(1)
print(entry[key])
PY
}

iso_pinned() {
  iso_meta url >/dev/null 2>&1
}

iso_ensure() {
  local out url size sha proxy
  out=$(iso_file)

  if ! iso_pinned; then
    info "no pinned ISO for '$WINDOWS_VERSION' - dockur will fetch it itself"
    return 0
  fi

  url=$(iso_meta url)
  size=$(iso_meta size)
  sha=$(iso_meta sha256)
  proxy=${PORTHOLE_ISO_PROXY:-}

  if [ -f "$out" ] && [ "$(stat -c %s "$out" 2>/dev/null || echo 0)" = "$size" ]; then
    info "ISO present, verifying checksum"
    if python3 "$PORTHOLE_ROOT/tools/fetch-iso.py" "$url" "$out" \
      --size "$size" --sha256 "$sha" --verify-only; then
      return 0
    fi
    warn "checksum mismatch - re-downloading"
    rm -f "$out"
  fi

  step "downloading $WINDOWS_VERSION ISO ($(human_size "$size"))"
  info "source: $url"
  local -a opts=(--size "$size" --sha256 "$sha" --workers 16)
  [ -n "$proxy" ] && opts+=(--proxy "$proxy")

  if ! python3 "$PORTHOLE_ROOT/tools/fetch-iso.py" "$url" "$out" "${opts[@]}"; then
    if [ -z "$proxy" ] && tcp_open 127.0.0.1 7890; then
      warn "direct download failed - retrying through 127.0.0.1:7890"
      python3 "$PORTHOLE_ROOT/tools/fetch-iso.py" "$url" "$out" \
        --size "$size" --sha256 "$sha" --workers 8 --proxy "http://127.0.0.1:7890" \
        || die "could not download the ISO (try: porthole iso --import <file>)"
    else
      die "could not download the ISO (try: porthole iso --import <file>)"
    fi
  fi
}

cmd_iso() {
  ensure_dirs
  local mode="download" file=""
  while [ $# -gt 0 ]; do
    case $1 in
      --verify) mode="verify"; shift ;;
      --import) [ $# -ge 2 ] || die "--import needs a file"; file=$2; mode="import"; shift 2 ;;
      *) die "iso: unknown argument: $1" ;;
    esac
  done

  case $mode in
    verify)
      iso_pinned || die "no pinned ISO for '$WINDOWS_VERSION'"
      python3 "$PORTHOLE_ROOT/tools/fetch-iso.py" "$(iso_meta url)" "$(iso_file)" \
        --size "$(iso_meta size)" --sha256 "$(iso_meta sha256)" --verify-only
      ;;
    import)
      [ -f "$file" ] || die "no such file: $file"
      iso_pinned || die "no pinned ISO for '$WINDOWS_VERSION'"
      local size sha
      size=$(iso_meta size)
      sha=$(iso_meta sha256)
      if [ "$(stat -c %s "$file")" != "$size" ]; then
        die "size mismatch: $file is $(stat -c %s "$file") bytes, expected $size"
      fi
      step "importing $file"
      cp -f -- "$file" "$(iso_file)"
      chmod 644 "$(iso_file)"
      python3 "$PORTHOLE_ROOT/tools/fetch-iso.py" "$(iso_meta url)" "$(iso_file)" \
        --size "$size" --sha256 "$sha" --verify-only \
        || die "imported file failed the checksum check"
      ;;
    download)
      iso_ensure
      ;;
  esac
}
