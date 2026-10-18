# Decisions

Short records of the choices that shaped porthole, including the ones made by
ruling something out.

---

## ADR-1: dockur/windows in Podman, not libvirt/QEMU directly

**Decision.** The VM is a container from `ghcr.io/dockur/windows`, run by
rootless Podman, pinned by digest.

**Why.** Libvirt pulls in a daemon, storage pools, a network stack and a
separate app for the console. dockur gives the same QEMU/KVM VM with one
`podman run`: unattended Windows installation, an OEM hook for provisioning,
an SMB share into the guest, a web console, and an ACPI-aware lifecycle. The
whole VM becomes a single container we can pause, stop and delete.

**Consequences.** Upgrading means changing a digest, not a distro package.
The VM always runs as the same user, and `podman pause` gives us the
"instant resume, zero CPU" property for free.

---

## ADR-2: fullscreen desktop session, not RemoteApp / RAIL

**Decision.** `xfreerdp +f` on a normal desktop session, with the app
maximised inside it.

**Why.** RAIL (RemoteApp) was implemented first and worked, but in a Windows
session it produced an extra top-level window titled `System32` that could not
be attributed to a process, survived `XUnmapWindow` (it came back), and made
the whole setup unusable. In a desktop session the same phenomenon is at worst
a visible folder that can be closed — it stops being fatal.

**Trade-off.** No native window decorations, no per-app taskbar entry, no
mixing several Windows apps into the Linux desktop. For a chat client that is
used maximised anyway, this costs nothing.

**Escape hatch.** `session.mode = "window"` gives a normal windowed session.
RAIL notes are kept in `docs/PLAN.md` §2 in case it is ever worth revisiting.

---

## ADR-3: assert the things that already burned us

**Decision.** Argument building refuses `/network:` and requires the RDP port
to be bound to `127.0.0.1`; encoding rules are enforced by `make check`.

**Why.** `/network:lan` in a RAIL session made the server reset the connection
(`ERRCONNECT_CONNECT_TRANSPORT_FAILED`), and it took a long bisect to find.
Windows scripts that lost their CRLF silently broke provisioning. These are
cheap assertions that turn a two-hour debugging session into an immediate,
readable error.

---

## ADR-4: tiny10

**Decision.** Default `VERSION=tiny10` (NTDEV's debloated Windows 10 22H2 x64).

**Why.** 3.6 GB ISO, ~10 GB installed, no Defender, no Store churn, no update
reboots — which matters a lot for a VM that is paused most of the time. Min
specs are 2 GB RAM / 10 GB disk, so 4 GB / 32 GB is comfortable.

**Risk.** Debloating can remove components an app needs (media foundation,
WebView2, printing). `ltsc10` is the fallback: one line in the profile and a
reset, with all components present and Microsoft-supported.

---

## ADR-5: pause instead of shutdown

**Decision.** Closing the window runs `podman pause`; a real shutdown only
happens on `porthole down` or after an idle timeout.

**Why.** Measured: paused QEMU uses 0.0 % CPU, resume takes ~1 s, and RAM
stays allocated. A cold boot is 60–90 s on 2 vCPU, and Windows insists on
showing a login screen again.

**Consequence.** A paused VM still holds 4 GB of RAM. That is the knob
`lifecycle.stop_after_idle_min` exists for.

---

## ADR-6: what the first real install taught us

Recorded after building the VM once end to end (2026-10-19).

**The dockur OEM hook runs twice, and the first time it is SYSTEM.**
`C:\OEM\install.bat` is launched from `SetupComplete.cmd` at the end of
setup (session 0, as SYSTEM) and again from `FirstLogonCommands`. Anything
written to `HKCU` or `%APPDATA%` in the first pass lands in SYSTEM's profile
and is useless. The second pass is the one that matters, so every step has to
be idempotent and safe to run as either user.

**Windows installation is fast, the OOBE is not.** Tiny10 reached the desktop
files in about four minutes, then sat on "It's taking a bit longer than
expected" indefinitely. A hard reset (`system_reset` through the QEMU monitor)
took it straight to the desktop. The provisioning script had already run by
then — that screen is OOBE, not setup.

**Never execute an installer from the SMB share.** `\\host.lan\Data\…exe`
triggers the "Open File - Security Warning" dialog, and because
`Start-Process` waits on it the provisioning log stalls for as long as the
dialog is up. `30-app.ps1` now copies the file to `%TEMP%` and unblocks it
first.

**The install path is not the one you guess.** WeCom lands in
`C:\Program Files (x86)\WXWork`, not `C:\Program Files`. The script now
resolves the executable from the uninstall registry keys before giving up.

**explorer.exe rewrites `StuckRects3` on exit.** Patching the taskbar settings
and *then* killing explorer undoes the patch. Stop explorer first, write the
registry, start explorer again.

**The guest display caps the RDP session.** With the basic display driver the
guest offers at most 1600x900, so a 4096x2560 fullscreen window shows the
desktop in a corner surrounded by black. Until a proper virtio-gpu driver is
in the image, the default is a 1600x900 window (`session.mode = "window"`);
`fullscreen` is implemented and works as soon as the guest can match the
screen size.
