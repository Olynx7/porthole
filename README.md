# porthole

[![check](https://github.com/Olynx7/porthole/actions/workflows/check.yml/badge.svg)](https://github.com/Olynx7/porthole/actions/workflows/check.yml)

Run **one Windows application** as a fullscreen window on Linux.

`porthole` boots a tiny Windows VM (Podman + QEMU/KVM via [dockur/windows][]),
connects to it with FreeRDP, and hides the "it is a whole desktop" part behind
a few cosmetic tweaks. Close the window and the VM is paused — CPU at zero,
memory kept — so the next launch is instant and your login state survives.

Built for **企业微信 (WeCom)** on Fedora. The VM and provisioning pipeline is
profile-driven, but a handful of placeholders (the process name watched by the
fit helper, the install-path fallbacks) are still WeCom-specific — see
*Known limitations* below.

[dockur/windows]: https://github.com/dockur/windows

```
┌─ Linux ───────────────────────────────────┐
│  porthole run                             │
│   ├─ podman ─► QEMU/KVM ─► tiny10 (VM)    │   ┌───────────────────────┐
│   └─ xfreerdp +f ─────────────────────────┼──►│  企业微信 (maximised)  │
│                                           │   └───────────────────────┘
└───────────────────────────────────────────┘
```

## Quick start

```sh
git clone git@github.com:Olynx7/porthole.git ~/Proj/porthole
cd ~/Proj/porthole
make install            # code -> ~/.local/lib/porthole, entry in the app menu
porthole provision -w   # download ISO, install Windows, provision it (~40 min)
porthole run            # open WeCom; closing the window pauses the VM
```

Once it is provisioned, a normal session looks like this:

```
$ porthole status
profile      wecom  (/home/olynx/.local/lib/porthole/config/profiles/wecom.toml)
image        ghcr.io/dockur/windows@sha256:32cc9271...
windows      tiny10  (2 vCPU / 4G RAM / 32G disk)
container    porthole-wecom  [paused]
rdp          127.0.0.1:3391  [inactive (VM paused)]
console      http://127.0.0.1:8006/
data         /home/olynx/.local/share/porthole/wecom  (on disk: 17G)
provision    done
```

First run needs one manual step: scan the WeCom QR code. Everything after
that is automatic, and the login state lives inside the VM disk.

## Commands

| command | what it does |
|---|---|
| `porthole run` | start/resume the VM, open the app fullscreen |
| `porthole shell` | plain windowed desktop session, for debugging |
| `porthole status` | container, RDP port, provisioning stage, disk usage |
| `porthole provision -w` | first-time install, then wait for completion |
| `porthole logs -f` | follow the container log |
| `porthole pause` / `resume` | pause releases CPU but keeps RAM and state |
| `porthole down` | graceful ACPI shutdown |
| `porthole reset -y` | throw the container away (`--all`: also the VM disk) |
| `porthole doctor -b` | diagnostics tarball to attach to a bug report |
| `porthole iso --verify` | check the ISO checksum |

Exit codes: `0` ok, `2` usage/config, `3` VM not ready, `4` RDP failure,
`5` provisioning failure.

## Configuration

Profiles are TOML files, so switching apps or Windows editions is a one-line
edit (`~/.config/porthole/profiles/wecom.toml` overrides the shipped default):

```toml
[vm]
version = "tiny10"     # tiny10 | ltsc10 | 10 | 11
cpus    = 2
ram     = "4G"
disk    = "32G"

[session]
mode          = "fullscreen"
grab_keyboard = false  # keep Super / Alt+Tab for GNOME
dpi_scale     = 125

[app]
exe       = 'C:\Program Files\WXWork\WXWork.exe'
installer = "WeCom_5.0.12.6018.exe"
```

`porthole config show` prints what is actually in effect.

## Layout

```
~/.local/lib/porthole/            code (this repo)
~/.local/share/porthole/wecom/    VM disk, shared folder, OEM scripts
~/.config/porthole/               profile overrides, secrets (0600), state
~/.local/state/porthole/          logs, doctor bundles
```

Nothing outside these paths is touched, and `porthole uninstall --purge -y`
removes all of it.

## Requirements

Fedora (or any distro with Podman), `/dev/kvm`, ~25 GB of disk, and
`xfreerdp` 3.x (`dnf install freerdp`). Rootless Podman is fine.

## Status icon

`make install` also drops a status icon into the top bar (a StatusNotifierItem,
hosted by the AppIndicator extension) and an autostart entry for it:

| action | result |
|---|---|
| left click | open / focus the application |
| right click | 显示企业微信 / 退出（停止容器） |
| hover | current VM state (paused / running / stopped) |

Minimising the window pauses the container, restoring it resumes; closing the
window pauses as well.

## Known limitations

- **One application per VM.** Each profile provisions its own Windows install
  (~13 GB). Sharing a single VM between several apps is designed but not built.
- **A few WeCom-specific bits remain** in `windows/40-fit.ps1` (window fitting,
  process name) and `windows/30-app.ps1` (install-path fallbacks). Another app
  needs those edited, not just a new profile.
- **The OOBE stage hangs** on this tiny10 image in a KVM guest. It needs one
  hard reset through the QEMU monitor to reach the desktop — the provisioning
  script has already run by then, so nothing is lost.
- **Clipboard needs two Ctrl+V** for the first paste: Wayland → XWayland →
  FreeRDP is an asynchronous round trip and the guest's edit control gives up
  before the data arrives.
- **The Windows key is disabled inside the guest** via a scancode map. Without
  it a compositor/client race can leave Windows convinced that Win is held
  down, and no client-side fix is reliable.

## Documentation

- [docs/PLAN.md](docs/PLAN.md) — architecture and the reasoning behind it
- [docs/RUNBOOK.md](docs/RUNBOOK.md) — install, reinstall, switch Windows, common failures
- [docs/DECISIONS.md](docs/DECISIONS.md) — why fullscreen instead of RemoteApp, and what we learned

## Licence

MIT
