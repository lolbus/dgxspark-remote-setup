# DGX Spark — Virtual Display + AnyDesk Remote Runbook

Rapid, repeatable setup for **headless AnyDesk remote desktop on NVIDIA DGX Spark / GB10 units
running Ubuntu 24.04 ARM64**, including automatic switching between a virtual (dummy) screen
when no monitor is attached and the unit's normal display config when one is plugged in.

This repo is the reference a **new DGX Spark unit** should be pointed at. The fast path is
[`docs/06-new-unit-runbook.md`](docs/06-new-unit-runbook.md) — roughly 15 minutes per unit.

---

## The problem this solves

A DGX Spark with no monitor attached has no connected DRM connector. Xorg therefore starts
with no screen (or does not start at all), so AnyDesk has nothing to capture. Symptoms:

| Symptom | Underlying cause |
|---|---|
| AnyDesk connects, screen is black or 640x480 | X started with no real mode / fell back |
| `Display server is not supported` in the AnyDesk window | The session is Wayland, not X11 |
| AnyDesk service running but unit shows offline / no ID | AnyDesk started before any X server existed |
| Desktop appears only while a monitor is plugged in | No virtual screen configured |

The fix is a **dummy Xorg screen** that exists whether or not hardware is attached, plus a
**hotplug-driven switcher** so a physically attached monitor still works normally.

## What gets installed

```
                 +-------------------------+
   DRM hotplug   |  udev rule              |
   (monitor in/  |  99-drm-hotplug.rules   |
    monitor out) +-----------+-------------+
                             | starts (no-block)
                 +-----------v-------------+
                 | display-autoswitch      |   oneshot systemd unit
                 | .service                |   also runs at boot,
                 +-----------+-------------+   before display-manager
                             |
                 +-----------v-------------+
                 | display-autoswitch.sh   |
                 | reads /sys/class/drm/*  |
                 +-----+-------------+-----+
                       |             |
       no monitor ->   |             |   <- monitor connected
    /etc/X11/xorg.conf |             | /etc/X11/xorg.conf
    := xorg.conf.dummy |             | := xorg.conf.physical (or removed
    (1920x1080 virtual)|             |  entirely, = stock auto-detect)
                       +------+------+
                              | restart display-manager ONLY if changed
                       +------v------+
                       | GDM (X11)   | WaylandEnable=false
                       +------+------+
                              |
                       +------v------+
                       | AnyDesk     | unattended password, arm64 .deb
                       +-------------+
```

## Quick start (on the unit, over SSH)

> Do this over **SSH**, never over AnyDesk. The installer restarts the display manager,
> which kills any AnyDesk session you are sitting in.

```bash
git clone <this-repo-url> dgx-virtualscreen && cd dgx-virtualscreen
sudo ./scripts/preflight.sh                 # reports, changes nothing
sudo ./scripts/install-virtual-display.sh   # dummy screen + autoswitch + X11 forcing
sudo ./scripts/install-anydesk.sh           # arm64 AnyDesk + unattended password
./scripts/healthcheck.sh                    # one-screen status, exit 0 = good
```

`scripts/install-anydesk.sh` prints the unit's AnyDesk ID at the end. Record it in
[`UNIT-INVENTORY.md`](UNIT-INVENTORY.md) and commit.

## Repo layout

| Path | What it is |
|---|---|
| `docs/01-overview.md` | Why headless AnyDesk breaks, the three options, why this one |
| `docs/02-prerequisites.md` | Everything needed before you start, including what is assumed already present |
| `docs/03-anydesk-install.md` | AnyDesk arm64 install, unattended access, service |
| `docs/04-virtual-display.md` | The dummy Xorg screen and its alternatives |
| `docs/05-autoswitch.md` | Hotplug detection, the switcher, the systemd/udev wiring |
| `docs/06-new-unit-runbook.md` | **The 15-minute path for a brand-new unit** |
| `docs/07-verification.md` | Post-install checks, each with a pass/fail branch |
| `docs/08-troubleshooting.md` | Sequential diagnostics — follow the branches, do not skim |
| `scripts/` | Idempotent installers, the switcher, health check, uninstall |
| `config/` | Xorg variants, udev rule, systemd unit — the files the scripts install |
| `UNIT-INVENTORY.md` | Per-unit record: hostname, AnyDesk ID, Tailscale IP, state |

## Scope and assumptions

- NVIDIA GB10 (DGX Spark class), 128 GB unified memory, **Ubuntu 24.04 ARM64 / DGX OS 7**.
- GNOME on GDM3. If the unit runs a different display manager, see `docs/08-troubleshooting.md`.
- An out-of-band shell (SSH, ideally over Tailscale) already works. **This is mandatory** —
  it is the only way back in if the display stack fails to come up.

## Markers used in these docs

- `VERIFY-ON-UNIT` — value or path that differs between units or driver versions. Confirm it
  on the box before copying. Do not propagate an unverified value into a new unit's config.
- `DESTRUCTIVE` — the step restarts the display manager or logs out the desktop session.

## Contributors

See [`CONTRIBUTORS.md`](CONTRIBUTORS.md).
