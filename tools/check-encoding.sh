#!/usr/bin/env bash
# check-encoding.sh - guard the line-ending / encoding rules that bit us before.
#
#   *.bat *.cmd *.ps1 *.reg : ASCII + CRLF, no BOM
#   other text files        : UTF-8 + LF, no BOM
#
# cmd.exe and the dockur image's batch normaliser both misbehave on LF-only
# .bat files, and PowerShell rejects wrapped lines in CRLF-less scripts.
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

exec python3 - "$root" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
WINDOWS_SUFFIXES = {".bat", ".cmd", ".ps1", ".reg"}
TEXT_SUFFIXES = {".sh", ".py", ".toml", ".md", ".in", ".conf", ".example", ".lock"}
TEXT_NAMES = {"makefile", "version", "license"}
SKIP_DIRS = {".git"}

failures = []
checked = 0


def fail(rel, reason):
    failures.append(f"{rel}: {reason}")


for path in sorted(root.rglob("*")):
    if not path.is_file():
        continue
    rel_path = path.relative_to(root)
    if rel_path.parts and rel_path.parts[0] in SKIP_DIRS:
        continue

    rel = rel_path.as_posix()
    suffix = path.suffix.lower()
    name = path.name.lower()
    is_windows = suffix in WINDOWS_SUFFIXES
    is_text = suffix in TEXT_SUFFIXES or name in TEXT_NAMES

    if not (is_windows or is_text):
        continue

    checked += 1
    data = path.read_bytes()

    if data.startswith(b"\xef\xbb\xbf"):
        fail(rel, "has a UTF-8 BOM")
        continue

    if is_windows:
        if data.count(b"\n") != data.count(b"\r\n"):
            fail(rel, "expected CRLF line endings")
        if data and not data.endswith(b"\r\n"):
            fail(rel, "missing trailing CRLF")
        try:
            data.decode("ascii")
        except UnicodeDecodeError:
            fail(rel, "expected pure ASCII")
    else:
        if b"\r" in data:
            fail(rel, "expected LF line endings")
        try:
            data.decode("utf-8")
        except UnicodeDecodeError:
            fail(rel, "not valid UTF-8")

if failures:
    for failure in failures:
        print(f"encoding: {failure}")
    print(f"\nencoding check failed ({len(failures)} of {checked} files)")
    sys.exit(1)

print(f"encoding check passed ({checked} files)")
PY
