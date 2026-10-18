# Runbook

Operational procedures. Everything here assumes the code lives in
`~/.local/lib/porthole` (installed) or `~/Proj/porthole` (checkout — run
`./bin/porthole` instead of `porthole`).

---

## 1. First install

```sh
make install
porthole provision -w
```

`provision` does, in order:

1. generate the Windows password → `~/.config/porthole/secrets/wecom.env` (0600)
2. download the pinned tiny10 ISO → `~/.local/share/porthole/wecom/storage/custom.iso`
3. render `C:\OEM` scripts from `windows/` into `.../wecom/oem/`
4. copy the app installer into `.../wecom/shared/` (visible as `\\host.lan\Data`)
5. create and start the container

Then, **inside** the VM, the unattended Windows installation runs
(25–35 min on 2 vCPU) and `C:\OEM\install.bat` configures everything:
RDP + session policies, taskbar/wallpaper/lock screen, the app install, and a
maximised startup shortcut. Progress is published back through the SMB share
as `.../wecom/shared/porthole-status.json`.

Watch the VM screen at <http://127.0.0.1:8006/>.

## 2. Daily use

```sh
porthole run          # fullscreen; closing the window pauses the VM
porthole status
porthole down         # when you want the RAM back
```

`Ctrl+Alt+Enter` toggles fullscreen. The floatbar (top of the screen while in
fullscreen) has a ✕ that disconnects and therefore pauses the VM.

## 3. Reinstall from scratch

```sh
porthole reset --all -y     # container + VM disk (ISO is kept)
porthole provision -w
```

## 4. Switch Windows edition

Edit the profile, then reset:

```toml
[vm]
version = "ltsc10"   # tiny10 | ltsc10 | 10 | 11
```

```sh
porthole reset --all -y && porthole provision -w
```

`tiny10` is pinned in `tools/iso.lock`, so `porthole iso` can pre-download and
verify it. Other editions are fetched by the container image itself.

## 5. Add another application

Copy `config/profiles/wecom.toml` to `~/.config/porthole/profiles/<name>.toml`,
change `profile.id`, `app.exe`, `app.installer` and the ports, then:

```sh
porthole -p <name> provision -w
porthole -p <name> run
```

---

## Troubleshooting

### The window opens but stays on "please wait"

Windows is still installing. `porthole logs -f` and the console at :8006 show
the screen. First boot on 2 vCPU really does take half an hour.

### The first boot hangs on "It's taking a bit longer than expected"

That is the OOBE, not the installer, and it can sit there forever on a tiny10
image. Hard-reset the VM from the QEMU monitor and it boots to the desktop:

```sh
podman exec porthole-wecom python3 -c '
import socket, time
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect("/run/shm/monitor.sock"); time.sleep(0.3)
s.sendall(b"system_reset\n"); time.sleep(1)'
```

`C:\OEM\install.bat` has already run at that point; re-run it inside the
guest if the app is missing.

### Fullscreen shows the desktop in a corner

The guest cannot switch to the screen resolution: the basic display driver
tops out at 1600x900, so a 4096x2560 window is mostly black. Use
`session.mode = "window"` (the current default) until the guest has a working
virtio-gpu driver and can match the screen size.

### `RDP did not come up`

```sh
porthole status                 # is the port listening?
porthole logs --lines 200
porthole shell                  # if the port *is* open
```

If port 3391 never opens after provisioning finished, the guest's RDP listener
is off — connect to the console at :8006, log in, and run
`C:\OEM\10-rdp.ps1` by hand (right-click → *Run with PowerShell*).

### The taskbar still shows

`20-desktop.ps1` patches `StuckRects3`. If it did not take, run
`C:\OEM\20-desktop.ps1` again inside a `porthole shell` session — it is
idempotent. As a last resort set `[desktop] tweaks = false` and live with it.

### Chinese text looks tiny or blurry

```sh
porthole run --dpi 150
```

Then persist it in the profile (`session.dpi_scale`) and re-run
`C:\OEM\20-desktop.ps1` once — the guest needs the DPI change too.

### The VM is sluggish

4 GB is the floor for Windows 10 + WeCom. Bump it:

```toml
[vm]
ram  = "6G"
cpus = 4
```

No reinstall needed — `porthole down && porthole run`. Resource limits are
applied on container creation, so `ram`/`cpus` changes need
`porthole reset -y` (keeps the disk) rather than a plain restart.

### Everything is broken, give me a bundle

```sh
porthole doctor -b
# ~/.local/state/porthole/doctor-<stamp>.tar.gz
```

### Remove porthole completely

```sh
porthole uninstall --purge -y
```

That stops and deletes the container, removes the code, the desktop entry, the
VM disk, the config and the secrets.

---

## Exit codes

| code | meaning | first thing to try |
|---|---|---|
| 0 | ok | — |
| 2 | usage / config / missing dependency | `porthole config show` |
| 3 | VM not ready | `porthole status`, `porthole logs` |
| 4 | RDP session failed | `porthole shell` |
| 5 | provisioning failed | `C:\OEM\porthole.log` inside the VM |
