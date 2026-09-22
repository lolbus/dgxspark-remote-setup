# 03 — AnyDesk install and unattended access (ARM64)

Run this **after** `install-virtual-display.sh`. `install-anydesk.sh` refuses to proceed if
GDM is not pinned to X11, because installing AnyDesk onto a Wayland session produces a unit
that looks healthy and shows a black screen.

## Package

AnyDesk ships arm64 `.deb` packages on the `/rpi/` download path. The path name is historical
(Raspberry Pi); the package is plain arm64 and installs on Ubuntu 24.04 ARM64.

```
https://download.anydesk.com/rpi/anydesk_8.0.4-1_arm64.deb
```

The APT repository `deb http://deb.anydesk.com/ all main` is **not** a substitute here — pin
the direct `.deb` so every unit in the fleet lands on the same version.

```bash
sudo ./scripts/install-anydesk.sh --set-password --open-firewall
```

To pin a different version:

```bash
sudo ./scripts/install-anydesk.sh --version 8.0.4-1
```

## Settings that matter, and why

| Field | Value | Reason |
|---|---|---|
| `WaylandEnable` (in `/etc/gdm3/custom.conf`) | `false` | AnyDesk captures X11 only. Left at the Ubuntu 24.04 default, incoming sessions fail with `Display server is not supported` |
| Unattended password | 12+ chars, from the password manager | Set via `echo <pw> \| sudo anydesk --set-password`. Without it, every connection needs somebody at the unit to click Accept — which defeats the purpose on a headless box |
| `AutomaticLoginEnable` / `AutomaticLogin` | `true` / admin username | Makes the unit reach a full desktop after reboot with nobody present. Without it AnyDesk shows the GDM greeter and you must type the account password remotely each reboot |
| AnyDesk service (`systemctl enable --now anydesk`) | enabled | The ID is only registered while the service runs; a disabled service means the unit never appears online |
| UFW rule TCP 7070 | allow (optional) | AnyDesk's direct/LAN path. Relay connections over outbound 443/6568 work without it, at higher latency |
| Outbound 443 and 6568 | must be permitted | How the unit registers its ID and reaches the relay. If these are blocked, `anydesk --get-id` returns nothing |
| Sleep/suspend targets | masked | A remote-only unit that suspends is unreachable until somebody presses its power button |

## Commands you will actually use on the unit

| Command | What it does |
|---|---|
| `anydesk --get-id` | Prints the numeric ID to give to the person connecting |
| `anydesk --get-alias` | Prints the alias, if one has been assigned in an AnyDesk account |
| `echo 'pw' \| sudo anydesk --set-password` | Sets or replaces the unattended-access password. Requires root |
| `sudo systemctl restart anydesk` | Restart after any display-stack change; AnyDesk does not always re-attach to a new X server on its own |
| `journalctl -u anydesk -n 100 --no-pager` | Service-level errors |
| `~/.anydesk/` | Per-user state. `/etc/anydesk/` holds system-wide config — VERIFY-ON-UNIT, layout differs between AnyDesk 6 and 8 |

## Security notes

- The unattended password is the **only** control on an ID that is reachable from the public
  internet. Treat it like a root password: password manager, per-unit, rotated when someone
  leaves.
- Enabling autologin means anyone with physical access to the unit gets a logged-in desktop.
  On a rack in a controlled room that is an acceptable trade; on a desk it is not. Record the
  decision per unit in `UNIT-INVENTORY.md`.
- Do not commit the password, an AnyDesk `service.conf`, or `~/.anydesk/` contents to this
  repo. `.gitignore` blocks the obvious names; it cannot save you from `git add -f`.
- If the unit must not be reachable from outside the tailnet, do not rely on AnyDesk's access
  control for that — block outbound AnyDesk at the firewall and reach the desktop over the
  tailnet instead.

## Source

AnyDesk Linux downloads and CLI reference:
- AnyDesk Linux downloads — https://anydesk.com/en/downloads/linux
- Command-line interface for Linux — https://support.anydesk.com/docs/command-line-interface-for-linux
