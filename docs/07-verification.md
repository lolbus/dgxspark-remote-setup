# 07 — Verification

`scripts/healthcheck.sh` runs all of this. This page is what each check means, so a failure
tells you something instead of just being red.

Run it as root to include the resolution check:

```bash
sudo ./scripts/healthcheck.sh
```

## What each check proves

| Check | Passes when | A failure means |
|---|---|---|
| `sshd active` | The recovery channel exists | You are one bad Xorg config away from a site visit. Fix before anything else |
| `tailscale ip` | The unit is on the tailnet | Only a warning if the unit is reachable another way |
| `physical monitor` | Connector states were read | Lists the connectors; this is the input the switcher decides on |
| `mode matches hardware` | Detected hardware and installed config agree | The switcher did not run, or ran and failed. Log: `/var/log/display-autoswitch.log` |
| `display-autoswitch.service enabled` | It will run on the next boot | The unit will come back from a reboot in the wrong mode |
| `hotplug udev rule present` | Plugging a monitor in will be noticed | Hotplug switching is dead; boot-time switching still works |
| `GDM pinned to X11` | `WaylandEnable=false` | AnyDesk will show `Display server is not supported` or a black screen |
| `display-manager active` | GDM is up | No X server, therefore nothing for AnyDesk to capture |
| `Xorg running` | An X server process exists | Same as above. Check `/var/log/Xorg.0.log` |
| `active resolution` | `xrandr` reports a mode | A dummy screen with no mode means the modelines or `Virtual` are wrong |
| `anydesk package / service` | Installed and running | The ID is only registered while the service runs |
| `AnyDesk ID` | An ID was assigned | Empty means outbound 443/6568 is blocked, or the service has not reached the relay yet |
| `sleep targets masked` | The unit cannot suspend itself | A warning, not a failure — but a remote-only unit that suspends is unreachable |

## Manual spot checks

```bash
# the decision log — read this first, always
sudo tail -40 /var/log/display-autoswitch.log

# what config is actually live
ls -l /etc/X11/xorg.conf && head -5 /etc/X11/xorg.conf

# which driver X actually loaded (should say "dummy" in headless mode)
sudo grep -iE 'Loading.*(dummy|nvidia)|Screen.*initialised|(EE)' /var/log/Xorg.0.log | tail -20

# session type of the logged-in desktop — must be x11
loginctl list-sessions
loginctl show-session <id> -p Type

# AnyDesk's own view
anydesk --get-id
sudo journalctl -u anydesk -n 50 --no-pager
```

## Acceptance criteria for calling a unit done

1. `healthcheck.sh` exits 0 with no FAIL lines.
2. An AnyDesk connection from another machine reaches a usable 1920x1080 desktop using only
   the ID and the unattended password, with nobody at the unit.
3. After `sudo reboot`, criterion 2 still holds with no manual step.
4. The unit's row exists in `UNIT-INVENTORY.md` with today's date.

Criterion 3 is the one people skip. It is also the only one that proves the unit survives a
power cut.

If a unit cannot be made to pass, roll it back to stock with `sudo ./scripts/uninstall.sh`
and re-run [`06-new-unit-runbook.md`](06-new-unit-runbook.md) from Step 2 rather than
layering fixes on a half-built unit.
