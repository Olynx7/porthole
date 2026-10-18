#!/usr/bin/env python3
"""Flatten a porthole TOML profile into shell assignments.

Emits lines like CFG_VM_CPUS=2 so that bash can `source` them. Nested
tables become underscore-joined names; arrays are newline-joined and get
an extra <NAME>_COUNT key.
"""
import shlex
import sys

import tomllib


def flatten(prefix, obj, out):
    for key, value in obj.items():
        name = f"{prefix}_{str(key).upper().replace('-', '_')}"
        if isinstance(value, dict):
            flatten(name, value, out)
        elif isinstance(value, list):
            out.append((f"{name}_COUNT", str(len(value))))
            joined = "\n".join("" if v is None else str(v) for v in value)
            out.append((name, joined))
        elif isinstance(value, bool):
            out.append((name, "true" if value else "false"))
        elif value is None:
            out.append((name, ""))
        else:
            out.append((name, str(value)))


def main(argv):
    if len(argv) != 2:
        print("usage: toml2env.py <profile.toml>", file=sys.stderr)
        return 2
    with open(argv[1], "rb") as fh:
        data = tomllib.load(fh)
    out = []
    flatten("CFG", data, out)
    for key, value in out:
        print(f"{key}={shlex.quote(value)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
