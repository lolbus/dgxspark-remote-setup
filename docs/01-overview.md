# 01 — Overview: why headless AnyDesk breaks, and which fix was chosen

## The failure

AnyDesk on Linux captures an **X11 screen**. A screen exists only if the X server has a
connected output with a valid mode. On a DGX Spark with no monitor:

- `/sys/class/drm/card*-*/status` reports every connector `disconnected`.
- Xorg starts with no screen, falls back to a minimal one, or fails to start.
- GDM on Ubuntu 24.04 additionally defaults to **Wayland**, which AnyDesk cannot capture at
  all — the client shows `Display server is not supported`.

Net effect: the AnyDesk service runs, the unit may even show an ID, and every incoming
session lands on a black or unusable screen.

## Options considered

### Point 1: does a hardware EDID emulator solve it with no software risk?

**Point title: HDMI/DP dummy plug**

- A passive EDID emulator dongle makes the connector report `connected` with a real mode, so
  the stock NVIDIA X11 path works untouched — no Xorg config, no switcher, no failure mode
  that can lock you out of the box.
- It costs under SGD 15 and survives OS upgrades, driver changes and reimaging.
- It requires somebody to physically plug it into the unit. `dxclabs-dgxspark` (Dell) is
  **remote-access only**, so nobody can fit one without a site visit.
- It occupies a display port that a technician may later need, and it silently disappears as
  a dependency — a unit that gets its dongle pulled during a rack move fails with no log.

**Summary: fully solves the technical problem and carries the least software risk, but it
cannot be applied to a remote-only unit, which is the exact case this repo exists for. Keep
it as the recommended fix for units somebody can physically touch.**

### Point 2: does the NVIDIA driver's own forced-output option avoid a second driver?

**Point title: `ConnectedMonitor` + `CustomEDID` on the nvidia X driver**

- Keeps the desktop on the NVIDIA driver, so the X session stays GPU-accelerated and the
  desktop feels like the physical one.
- Needs a captured or synthesised EDID binary on disk per unit, and the connector name
  (`DP-0`, `HDMI-A-1`, …) differs between the Dell and HP GB10 boxes — VERIFY-ON-UNIT on
  every single unit, which is the opposite of a rapid repeatable setup.
- The option names and their behaviour on the GB10 / Tegra-class display stack are not
  guaranteed stable across driver releases; a driver bump can silently return the unit to a
  black screen.
- Forcing a fake output on the real connector fights with a real monitor when one is plugged
  in, so it does not compose cleanly with the auto-switch requirement.

**Summary: better desktop performance, but it makes every unit a one-off and couples the
remote-access path to NVIDIA driver internals. Rejected for a fleet runbook; keep it in
reserve if the dummy driver's software rendering ever becomes a bottleneck.**

### Point 3: does a software dummy screen give a uniform, fleet-wide procedure?

**Point title: `xserver-xorg-video-dummy` with a hotplug switcher — CHOSEN**

- One package and one Xorg file, byte-identical on every unit; nothing per-unit to verify
  except that the switcher picked the right mode.
- Installs and reverts entirely over SSH, which is the only channel guaranteed on a
  remote-only unit.
- Composes with a real monitor: the switcher removes the dummy config on hotplug and hands
  the display back to the stock NVIDIA auto-detect path.
- Costs GPU acceleration for the desktop — the dummy driver is a software framebuffer, so
  the remote desktop is fine for admin work and poor for 3D or video playback. **CUDA and
  the NVIDIA compute stack are untouched**; only the X desktop is software-rendered.
- Adds moving parts that can fail: a udev rule, a systemd unit, and a display-manager
  restart. The restart drops any live AnyDesk session.

**Summary: it is the only option that is both remote-applicable and identical across units,
and its one real cost — a software-rendered desktop — does not touch the workload these
boxes exist to run. The added moving parts are contained by making the switcher a no-op when
nothing changed, and by requiring SSH as the recovery channel.**

## The chosen architecture

```
boot ─┐
      ├─> display-autoswitch.service (--boot, before display-manager)
hotplug ─> udev 99-drm-hotplug.rules ─> display-autoswitch.service
                         │
                         v
          display-autoswitch.sh   reads /sys/class/drm/*/status
                         │
          ┌──────────────┴──────────────┐
    no connector                  connector connected
          │                              │
  cp xorg.conf.dummy             cp xorg.conf.physical, or
   -> /etc/X11/xorg.conf         rm /etc/X11/xorg.conf (auto-detect)
          │                              │
          └──────────────┬──────────────┘
                         │ only if the mode actually changed
                  restart display-manager
                         │
                 GDM, X11 only (WaylandEnable=false)
                         │
                      AnyDesk
```

Design rules the implementation follows:

1. **Idempotent.** Same mode as last time means no file write and no restart. Hotplug fires
   several events per plug; the switcher debounces and takes the lock.
2. **State is derived, not trusted.** `/run/display-autoswitch.state` is a cache; if it is
   missing (reboot clears `/run`), the mode is inferred from the file on disk.
3. **Absent `xorg.conf` is a valid state.** On stock DGX Spark there is no `/etc/X11/xorg.conf`
   at all, and that is exactly the right config when a monitor is attached. The physical
   variant is allowed to be an empty file meaning "remove it".
4. **Never restart the display manager at boot.** It has not started yet; restarting it there
   races GDM and can leave the unit with no greeter.

## Read next

- [`02-prerequisites.md`](02-prerequisites.md) — what you need before touching the unit.
- [`06-new-unit-runbook.md`](06-new-unit-runbook.md) — the fast path.
