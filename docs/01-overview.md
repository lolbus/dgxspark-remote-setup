# 01 — Overview

> **Provenance.** The mechanism described here is transcribed from
> [`../Manual-Direct-commands.txt`](../Manual-Direct-commands.txt), the procedure built and
> validated on `dxclabs-dgxspark`. That file is the source of truth. If this page and that
> file ever disagree, that file wins and this page is the bug.

## The failure

AnyDesk captures an X11 screen. A screen exists only if Xorg has an output with a valid
mode. With no monitor attached, the NVIDIA driver reports zero display devices, so the
desktop either does not come up or comes up unusable, and every AnyDesk session lands on a
black screen.

## The solution

Two complete Xorg configs on disk, and a service that copies the right one over
`/etc/X11/xorg.conf` and restarts GDM when the monitor state changes.

```
/etc/X11/display-modes/physical.conf    the unit's own DGX OS xorg.conf (Driver "nvidia")
/etc/X11/display-modes/headless.conf    dummy driver, 1920x1080
                    |
/usr/local/sbin/display-mode.sh  boot   before GDM: pick the config from the monitor count
                                 watch  poll every 5 s, switch + restart GDM on a change
                    |
/etc/systemd/system/display-mode.service
        ExecStartPre=display-mode.sh boot     (Before=display-manager.service gdm.service)
        ExecStart=display-mode.sh watch       (Restart=always, RestartSec=5)
```

Detection is the NVIDIA driver's own view, not DRM sysfs:

```bash
nvidia-xconfig --query-gpu-info | awk -F': *' '/Number of Display Devices/{print $2; exit}'
```

Greater than zero means a monitor is attached.

## The timing, and why it is asymmetric

| Parameter | Value | Effect |
|---|---|---|
| `POLL` | `5` | Seconds between checks |
| `PLUG_POLLS` | `2` | Monitor seen 2 polls running (~10 s) → switch to physical |
| `UNPLUG_POLLS` | `24` | Monitor gone 24 polls running (~120 s) → switch to headless |

Fast in, slow out. Every switch restarts GDM and logs out the desktop, so a monitor that
blips — powered off, KVM switched, cable jiggled — must not be able to bounce the box. Ten
seconds is quick enough that somebody standing at the unit with a cable does not wait; two
minutes is long enough that transient loss of signal is ignored.

If a monitor on this site drops its signal when powered off and you do not want that to
count as unplugged, raise `UNPLUG_POLLS`.

## Boot ordering

- The unit is `Before=display-manager.service gdm.service`, so `display-mode.sh boot` has
  already chosen the config by the time GDM starts.
- `boot` begins with `systemctl is-active --quiet gdm && exit 0`. That guard means the boot
  branch only acts at a real boot — if systemd restarts the watcher later, it does not
  re-decide underneath a running desktop.
- `boot` then waits up to 30 s for `nvidia-smi -L` to answer before querying the monitor
  count. Without that wait the driver may not be up yet, the query returns nothing, and a
  unit with a monitor attached would boot headless.

## Known behaviour

- Every switch restarts GDM, so any open desktop session — local or AnyDesk — is logged
  out. SSH, tmux, containers and model jobs are unaffected.
- The headless desktop runs on the dummy software framebuffer, so it is not GPU-accelerated.
  CUDA and every compute workload are untouched; only the X desktop is software-rendered.
