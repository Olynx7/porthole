# Changelog

## 0.1.0-dev

First working skeleton.

- CLI: `run`, `shell`, `up`, `down`, `pause`, `resume`, `status`, `logs`,
  `provision`, `iso`, `reset`, `doctor`, `uninstall`, `config`
- TOML profiles with per-key overrides, `wecom` and `notepad` shipped
- Parallel ranged ISO download (16 workers) with sha256 verification
- Container lifecycle on rootless Podman: create / start / pause / unpause /
  stop / remove, with a per-profile `flock` so two sessions cannot race
- Fullscreen FreeRDP session: `+f`, `-grab-keyboard`, floatbar, clipboard,
  audio, drive redirection, `WM_CLASS=porthole`
- Unattended Windows provisioning from `/oem`: RDP + session policies,
  taskbar/wallpaper/lock-screen clean-up, DPI, silent app install, maximised
  startup shortcut, status reported back through the SMB share
- `make check`: encoding/line-ending guard (ASCII+CRLF for `.bat`/`.ps1`,
  UTF-8+LF elsewhere) plus bash/python syntax checks
