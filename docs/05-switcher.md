# 05 — The switcher

> **Provenance.** `display-mode.sh` and `display-mode.service` in this repo are extracted
> verbatim from Steps 4 and 5 of
> [`../Manual-Direct-commands.txt`](../Manual-Direct-commands.txt). Do not edit them here to
> "improve" them without changing that file too.

## Components

| Path | Role |
|---|---|
| `/usr/local/sbin/display-mode.sh` | `boot` picks the config before GDM starts; `watch` polls and switches |
| `/etc/systemd/system/display-mode.service` | Runs `boot` as `ExecStartPre`, then `watch` as `ExecStart`, `Restart=always` |
| `/etc/X11/display-modes/` | The two configs |
| `journalctl -t display-mode` | Every switch, via `logger -t display-mode` |

## Detection

```bash
nvidia-xconfig --query-gpu-info | awk -F': *' '/Number of Display Devices/{print $2; exit}'
```

Greater than zero means a monitor is attached. This asks the NVIDIA driver, not DRM sysfs —
`nvidia-xconfig` is the only detection method validated on these boxes. If it is missing or
returns nothing, `monitor_present()` reads as zero and the unit pins itself to headless.

## Timing

| Parameter | Value | Effect |
|---|---|---|
| `POLL` | `5` | Seconds between checks |
| `PLUG_POLLS` | `2` | ~10 s of monitor present → switch to physical |
| `UNPLUG_POLLS` | `24` | ~120 s of monitor absent → switch to headless |

Asymmetric on purpose: every switch restarts GDM and logs the desktop out, so adopting a
monitor should be quick but dropping one must not be triggered by a blip. A monitor that
drops its signal when powered off counts as unplugged — if that is the behaviour on site,
raise `UNPLUG_POLLS`.

The counters reset on every switch and whenever the state flips, so the wait is 24
*consecutive* absent polls, not 24 cumulative.

## Boot path

```bash
systemctl is-active --quiet gdm && exit 0            # only decide at a real boot
for i in $(seq 1 30); do nvidia-smi -L >/dev/null 2>&1 && break; sleep 1; done
if monitor_present; then set_mode physical; else set_mode headless; fi
```

Two guards worth understanding before touching this:

- The `gdm` check stops the boot branch re-deciding underneath a running desktop when
  systemd restarts the watcher (`Restart=always`).
- The 30 s `nvidia-smi` wait exists because the driver may not be up when the unit starts.
  Query too early and a unit with a monitor attached boots headless.

## Tuning

Edit the values at the top of `/usr/local/sbin/display-mode.sh`, then:

```bash
sudo systemctl restart display-mode.service
```

Restarting the service does **not** restart GDM or re-run the boot decision — the `gdm`
guard sees GDM active and exits. The watcher picks up the new values and carries on.

Change the values in this repo's `scripts/display-mode.sh` too, or the next unit gets the
old ones.

## Watching it work

```bash
journalctl -t display-mode -b --no-pager     # this boot
journalctl -t display-mode -f                # live, for the plug/unplug test
systemctl status display-mode --no-pager
```
