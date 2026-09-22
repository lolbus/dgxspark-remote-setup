# 07 — Verification

> **Provenance.** Steps 7 and 8 of
> [`../Manual-Direct-commands.txt`](../Manual-Direct-commands.txt).
> `scripts/verify-display-mode.sh` runs the Step 7 command set and prints these branches
> alongside the output. `scripts/healthcheck.sh` is an addition, not part of that procedure.

## Step 7 — headless mode, over SSH

The original command set:

```bash
journalctl -t display-mode -b --no-pager
cmp -s /etc/X11/xorg.conf /etc/X11/display-modes/headless.conf && echo "XORG.CONF = HEADLESS"
grep -h 'LoadModule: "dummy"' /var/log/Xorg.0.log \
     /var/lib/gdm3/.local/share/xorg/Xorg.0.log 2>/dev/null
systemctl is-active display-mode gdm
```

| Output | Means |
|---|---|
| `switched to headless` + `XORG.CONF = HEADLESS` + a `LoadModule: "dummy"` line + `active` twice + AnyDesk shows the login screen | Headless mode works. Go to Step 8 |
| `switched to physical` with no monitor attached | Stop. Detection is wrong — paste the whole output |
| Headless, but `gdm` not active, or AnyDesk still black | Stop. Paste `systemctl status gdm --no-pager` |

## Step 8 — live switching, at the unit

```bash
journalctl -t display-mode -f
```

| Action | Expected | If not |
|---|---|---|
| Plug the monitor in | `switched to physical` within ~10 s, login screen on the monitor | Nothing within 30 s → Ctrl+C and run `sudo nvidia-xconfig --query-gpu-info \| grep -E "Number of Display Devices\|EDID Name"` with the monitor attached |
| Unplug the monitor | `switched to headless` about 120 s later, AnyDesk works again | Longer than ~3 min → check `UNPLUG_POLLS` and that the watcher is running |

## What each check actually proves

| Check | Proves |
|---|---|
| `switched to ...` in the journal | The switcher ran and made a decision. No line at all means the service never started |
| `XORG.CONF = HEADLESS` | The decision reached disk. A decision in the log with the wrong file live means `set_mode` failed — permissions or a full disk |
| `LoadModule: "dummy"` | Xorg actually loaded the dummy driver, rather than falling back. Without this the screen may exist but be unusable |
| `systemctl is-active display-mode gdm` | The watcher survives, and GDM came back after the switch |
| AnyDesk shows the login screen | End to end: a screen exists and AnyDesk can capture it |

## Acceptance criteria

1. `verify-display-mode.sh` shows the Step 7 pass pattern.
2. An AnyDesk connection from another machine reaches a usable 1920x1080 desktop using only
   the ID and the unattended password, with nobody at the unit.
3. After `sudo reboot`, criterion 2 still holds with no manual step.
4. Step 8 passed, or the unit is recorded as remote-only with Step 8 untested.
5. The unit's row exists in `UNIT-INVENTORY.md` with today's date.

Criterion 3 is the one people skip, and the only one that proves the unit survives a power
cut. If a unit cannot be made to pass, roll it back with `sudo ./scripts/rollback.sh` and
re-run from Step 2 rather than layering fixes on a half-built unit.
