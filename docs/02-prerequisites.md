# 02 — Prerequisites

## Assumed already present on the unit

These are taken as given. If any is missing, stop and fix it first — the rest of the runbook
depends on them.

- The unit itself, an NVIDIA GB10 box (DGX Spark class: Dell Pro Max GB10 or HP ZGX Nano GB10,
  128 GB unified memory).
- Its operating system already installed and booting (Ubuntu 24.04 ARM64 / DGX OS 7) with the
  GNOME desktop and the GDM3 login manager.
- A working administrator account with `sudo`.
- Outbound internet through whatever proxy or firewall the site uses, for `apt` and for the
  AnyDesk package download.
- The NVIDIA driver already installed and `nvidia-smi` returning the GPU.

## Required before you start

| # | What it is, in plain terms | The specific thing |
|---|---|---|
| 1 | A shell on the unit that does **not** depend on the desktop, so a broken display config cannot lock you out | OpenSSH server running (`ssh` / `sshd` systemd unit) |
| 2 | A network path to that shell that works from wherever you are, including off-site | Tailscale on the unit and on your machine (`tailscale`, the unit joined to your tailnet) — or a routed LAN/VPN address you can reach |
| 3 | The remote-desktop client you will connect with afterwards | AnyDesk client on your own machine (any platform) |
| 4 | The software framebuffer driver that provides the virtual screen | `xserver-xorg-video-dummy` (installed by the script; listed here so it appears in change requests) |
| 5 | The small X utilities used to read and set the resolution over SSH | `x11-xserver-utils`, which provides `xrandr` (installed by the script) |
| 6 | The remote-desktop server package for 64-bit ARM | `anydesk_8.0.4-1_arm64.deb` from `download.anydesk.com/rpi/` (downloaded by the script) |
| 7 | Somewhere safe to keep the unattended-access password | The team password manager. **Not this repo** — `.gitignore` blocks the obvious filenames but the only real control is not writing it down here |
| 8 | This repo on the unit | `git clone`, or `scp` the folder across if the unit has no git access |

## Optional, for units somebody can physically reach

| # | What it is, in plain terms | The specific thing |
|---|---|---|
| 9 | A plug that makes the graphics port believe a monitor is attached, removing the need for any of this software | HDMI or DisplayPort EDID emulator / "dummy plug" (match the unit's port; DP on the Dell Pro Max GB10 — VERIFY-ON-UNIT) |

If you fit item 9, you still install the autoswitch — it simply stays in `physical` mode and
does nothing. That keeps every unit on one identical config.

## Information to have in hand

| Field | Value | Reason |
|---|---|---|
| Unit hostname | e.g. `dxclabs-dgxspark` | Goes in `UNIT-INVENTORY.md`; also how you will tell two units apart in AnyDesk |
| Admin username | e.g. `dxcadmin` | Needed for `--autologin`, and it is the account whose desktop AnyDesk will show |
| Tailscale IP | e.g. `100.109.196.102` | Your recovery channel; record it before you change anything |
| Autologin required? | yes / no | `yes` means the unit reaches a full desktop after reboot unattended. `no` means every reboot leaves you at the GDM greeter needing the account password typed over AnyDesk |
| Unattended password | 12+ characters, stored in the password manager | The only barrier on an AnyDesk ID that is reachable from the internet |
| UFW in use? | yes / no | If yes, TCP 7070 must be allowed for direct/LAN AnyDesk connections; relay-only still works without it |

## Hard stop

`scripts/preflight.sh` exits non-zero and refuses to bless the unit if there is no active SSH
server. Do not work around that check. A failed Xorg config on a remote-only unit with no SSH
is a site visit, and on `dxclabs-dgxspark` there is no site to visit quickly.
