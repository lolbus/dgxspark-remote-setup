# 03 — AnyDesk install and unattended access (ARM64)

> **Provenance — read this first.** This page is **not** part of the validated procedure in
> [`../Manual-Direct-commands.txt`](../Manual-Direct-commands.txt), which covers the display
> switching only. The package URL and the CLI below come from AnyDesk's own documentation
> and have not been re-validated against `dxclabs-dgxspark`. Treat it as a starting point,
> not as a transcript of what was done.

Install it **after** the display mode is in place. On a headless unit with no display-mode
service there is no screen for AnyDesk to capture.

## Package

AnyDesk ships arm64 `.deb` packages on the `/rpi/` download path. The path name is
historical (Raspberry Pi); the package is plain arm64.

```
https://download.anydesk.com/rpi/anydesk_8.0.4-1_arm64.deb
```

```bash
sudo ./scripts/install-anydesk.sh --set-password --open-firewall
```

## Settings that matter

| Field | Value | Reason |
|---|---|---|
| Unattended password | 12+ chars, from the password manager | `echo <pw> \| sudo anydesk --set-password`. Without it every connection needs somebody at the unit to click Accept |
| AnyDesk service | `systemctl enable --now anydesk` | The ID is only registered while the service runs |
| Outbound 443 and 6568 | must be permitted | How the unit registers its ID and reaches the relay. Blocked means `anydesk --get-id` returns nothing |
| UFW rule TCP 7070 | allow (optional) | AnyDesk's direct/LAN path. Relay connections work without it, at higher latency |
| `WaylandEnable` in `/etc/gdm3/custom.conf` | leave alone unless needed | The validated build did not set it — an `/etc/X11/xorg.conf` is present and GDM uses X11. Set it to `false` only if AnyDesk reports `Display server is not supported` |

## Commands

| Command | What it does |
|---|---|
| `anydesk --get-id` | The numeric ID to give whoever is connecting |
| `anydesk --get-alias` | The alias, if one is assigned in an AnyDesk account |
| `echo 'pw' \| sudo anydesk --set-password` | Sets or replaces the unattended password. Requires root |
| `sudo systemctl restart anydesk` | Run after any display switch if the session stays black |
| `journalctl -u anydesk -n 100 --no-pager` | Service-level errors |

## Interaction with the switcher

Every mode switch restarts GDM, which tears down the X server AnyDesk was attached to. Any
open AnyDesk session is logged out and the desktop comes back fresh. If AnyDesk shows a
black screen after a switch rather than reconnecting cleanly, restart it.

## Security notes

- The unattended password is the only control on an ID reachable from the public internet.
  Password manager, per-unit, rotated when someone leaves.
- Do not commit the password or `~/.anydesk/` contents. `.gitignore` blocks the obvious
  names; it cannot stop `git add -f`.

Sources: AnyDesk Linux downloads (anydesk.com/en/downloads/linux) and Command-line interface
for Linux (support.anydesk.com/docs/command-line-interface-for-linux).
