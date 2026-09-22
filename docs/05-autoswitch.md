# 05 — The hotplug autoswitch

## Components

| Path | Role |
|---|---|
| `/usr/local/sbin/display-autoswitch.sh` | The logic. Detects connectors, selects a variant, restarts the display manager only on a real change |
| `/etc/systemd/system/display-autoswitch.service` | Oneshot unit. Runs at boot with `--boot`, and on every hotplug event with no flags |
| `/etc/udev/rules.d/99-drm-hotplug.rules` | Fires the unit on `ACTION=="change", SUBSYSTEM=="drm", ENV{HOTPLUG}=="1"` |
| `/run/display-autoswitch.state` | Cached current mode. Cleared on reboot; the script re-derives it from disk |
| `/run/lock/display-autoswitch.lock` | `flock` serialising the burst of events one plug generates |
| `/var/log/display-autoswitch.log` | Every decision, with timestamps. First place to look |

## Detection rule

A monitor counts as present when any file matching `/sys/class/drm/card*-*/status` contains
exactly `connected`, **excluding** connectors whose name contains `Writeback` or `Virtual`.

The exclusion is not cosmetic: several DRM drivers expose writeback connectors that report
`connected` permanently. Without the filter the unit pins itself into `physical` mode, never
installs the dummy config, and stays black forever.

> VERIFY-ON-UNIT: run `grep -H . /sys/class/drm/card*-*/status` on a new unit before trusting
> the switcher. If a connector you do not recognise reports `connected` with nothing plugged
> in, add it to the exclusion `case` in the script rather than working around it elsewhere.

## Behaviour

| Trigger | Flags | Restarts the display manager? |
|---|---|---|
| Boot | `--boot` | No. GDM has not started; restarting it there races the boot sequence |
| Monitor plugged in | none | Yes, if the mode actually changed |
| Monitor pulled out | none | Yes, if the mode actually changed |
| Re-run by hand after editing a variant | `--force` | Yes |
| Inspection | `--status` | No. Read-only, works without root |
| Rehearsal | `--dry-run` | No. Prints the intended actions |

A change of mode **drops any live AnyDesk session** — the display manager restart tears down
the X server the session was attached to. This is expected. Reconnect after ~15 seconds.

## Manual operation

```bash
# what does it think right now (no root needed)
/usr/local/sbin/display-autoswitch.sh --status

# rehearse
sudo /usr/local/sbin/display-autoswitch.sh --dry-run --force

# apply now — DESTRUCTIVE, restarts the display manager
sudo /usr/local/sbin/display-autoswitch.sh --force

# watch it decide
sudo tail -f /var/log/display-autoswitch.log
```

## Testing the hotplug path without a monitor

You cannot fake a DRM connector state, but you can prove the trigger chain fires:

```bash
sudo udevadm trigger --subsystem-match=drm --action=change
sudo journalctl -u display-autoswitch.service -n 30 --no-pager
```

The unit should run, log `no change`, and exit 0. If it never runs, the udev rule is the
problem, not the script — see [`08-troubleshooting.md`](08-troubleshooting.md) Step 4.

## Tuning

| Environment variable | Default | Effect |
|---|---|---|
| `DEBOUNCE_SECONDS` | `4` | Settle time before re-reading connector state on a hotplug. Raise if one plug produces two switches |
| `VARIANT_DIR` | `/etc/X11/autoswitch` | Where the variants live |
| `STATE_FILE` | `/run/display-autoswitch.state` | Cached mode |
| `LOG_FILE` | `/var/log/display-autoswitch.log` | Decision log |

Set them in a systemd drop-in, not by editing the script:

```bash
sudo systemctl edit display-autoswitch.service
# [Service]
# Environment=DEBOUNCE_SECONDS=8
```
