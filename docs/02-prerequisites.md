# 02 — Prerequisites

## Assumed already present on the unit

- The unit itself, an NVIDIA GB10 box (DGX Spark class: Dell Pro Max GB10 or HP ZGX Nano
  GB10, 128 GB unified memory), booting DGX OS / Ubuntu 24.04 ARM64 with GNOME on GDM.
- An administrator account with `sudo`.
- The NVIDIA driver installed, with `nvidia-smi` and `nvidia-xconfig` both working.
- **An existing `/etc/X11/xorg.conf` that declares `Driver "nvidia"` and drives a real
  monitor today.** Step 2 copies it to `physical.conf`; it is what the unit switches back to.
  Without it there is nothing to return to and the installer stops.
- Outbound internet for `apt` and the AnyDesk package.

## Required before you start

| # | What it is, in plain terms | The specific thing |
|---|---|---|
| 1 | A shell that does not depend on the desktop, since every switch restarts GDM | OpenSSH server running (`ssh` / `sshd`) |
| 2 | A network path to that shell that works off-site | Tailscale on the unit and on your machine, or a routed LAN/VPN address |
| 3 | The tool the switcher uses to count monitors | `nvidia-xconfig` (ships with the NVIDIA driver) |
| 4 | The software framebuffer driver that provides the headless screen | `xserver-xorg-video-dummy` (installed by Step 1) |
| 5 | The remote-desktop client you will connect with | AnyDesk client on your own machine |
| 6 | The remote-desktop server package for 64-bit ARM | `anydesk_8.0.4-1_arm64.deb` from `download.anydesk.com/rpi/` (downloaded by the script) |
| 7 | Somewhere safe for the unattended-access password | The team password manager. **Not this repo** |
| 8 | This repo on the unit | `git clone`, or `scp` the folder across |

## Optional, for the live-switch test only

| # | What it is, in plain terms | The specific thing |
|---|---|---|
| 9 | A monitor to plug in and pull out while watching the log | Any DP/HDMI monitor (the original build used a BenQ) |

Step 8 cannot be run without somebody at the unit. A remote-only box is built and verified
on Steps 1–7 alone; the live-switch path stays untested there, which is worth recording in
`UNIT-INVENTORY.md`.

## Information to have in hand

| Field | Value | Reason |
|---|---|---|
| Unit hostname | e.g. `dxclabs-dgxspark` | Goes in `UNIT-INVENTORY.md` |
| Tailscale IP | e.g. `100.109.196.102` | Your recovery channel; record it before changing anything |
| Unattended password | 12+ characters, in the password manager | The only barrier on an AnyDesk ID reachable from the internet |
| Monitor behaviour on site | does it drop signal when powered off? | If yes, `UNPLUG_POLLS` needs raising or the box will go headless 120 s after someone switches the screen off |

## Hard stop

`scripts/preflight.sh` exits non-zero if there is no active SSH server, if `nvidia-xconfig`
is missing, or if there is no `/etc/X11/xorg.conf` to save. Do not work around those checks —
each one makes the switcher either unrecoverable or permanently wrong.
