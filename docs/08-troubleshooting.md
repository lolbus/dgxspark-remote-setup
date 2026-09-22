# 08 — Troubleshooting

Work from **Step 1 downwards**. Each step ends in branches: one says stop and apply a fix,
the other says continue. Do not jump to the step whose title matches your symptom.

Everything here is run over SSH.

---

## Step 1 — Confirm you still have a way back in

```bash
systemctl is-active ssh || systemctl is-active sshd
tailscale ip -4 2>/dev/null
```

- **`active` and an IP** → continue to Step 2.
- **Inactive, or no route** → **stop.** Restore SSH (`sudo systemctl enable --now ssh`,
  check UFW allows 22/tcp). Nothing below is safe without it: every fix here restarts GDM.

---

## Step 2 — Confirm the switcher can see monitors at all

```bash
which nvidia-xconfig
nvidia-xconfig --query-gpu-info | grep -E "Number of Display Devices|EDID Name"
```

- **A count is printed, and it matches reality** (0 with nothing attached) → continue to
  Step 3.
- **`nvidia-xconfig: command not found`** → **stop and fix.** `monitor_present()` reads as
  zero without it, so the unit pins to headless and will never come back to a monitor.
  Reinstall the NVIDIA driver tooling, then re-run Step 2.
- **Command exists but prints nothing** → **stop and fix.** Usually the driver is not up.
  Check `nvidia-smi -L`. If the driver is fine and the query is still empty, the detection
  method does not work on this unit and the whole approach needs revisiting — paste the
  output rather than working around it.
- **A count is printed but it is wrong** (0 with a monitor attached, or the reverse) →
  **stop and fix.** Check the cable and that the monitor is powered. A monitor that drops
  signal when powered off reads as absent — that is expected behaviour, see Step 6.

---

## Step 3 — Confirm the service is running

```bash
systemctl is-enabled display-mode.service
systemctl is-active display-mode.service
systemctl status display-mode.service --no-pager | tail -20
```

- **enabled and active** → continue to Step 4.
- **Not enabled** → **stop and fix:** `sudo systemctl enable --now display-mode.service`.
  Re-run Step 3.
- **Enabled but inactive, restarting in a loop** → read the status output. `Restart=always`
  with `RestartSec=5` means a failing script retries every 5 s and fills the journal. The
  usual cause is `/usr/local/sbin/display-mode.sh` missing or not executable. Re-run
  `sudo ./scripts/install-display-mode.sh`, then re-run Step 3.

---

## Step 4 — Confirm the decision reached disk

```bash
journalctl -t display-mode -b --no-pager | tail -20
cmp -s /etc/X11/xorg.conf /etc/X11/display-modes/headless.conf && echo HEADLESS
cmp -s /etc/X11/xorg.conf /etc/X11/display-modes/physical.conf && echo PHYSICAL
```

- **A `switched to ...` line, and the live config matches it and matches Step 2** →
  continue to Step 5.
- **No journal entries this boot at all** → the boot branch exited early. That is what
  `systemctl is-active --quiet gdm && exit 0` does when GDM is already up, which is correct
  on a service restart but means the mode was never re-decided. Force it:
  `sudo /usr/local/sbin/display-mode.sh watch` in a terminal for one poll cycle, or reboot.
  Re-run Step 4.
- **A `switched to` line, but neither `cmp` matches** → `set_mode` wrote nothing, or
  `xorg.conf` was hand-edited afterwards. **Stop and fix:** check disk space (`df -h /`) and
  permissions on `/etc/X11/`, then
  `sudo cp /etc/X11/display-modes/headless.conf /etc/X11/xorg.conf`. Re-run Step 4.
- **The log says `physical` with no monitor attached** → go back to Step 2, last branch.

---

## Step 5 — Confirm Xorg came up on the right driver

```bash
systemctl is-active gdm
grep -h 'LoadModule: "dummy"' /var/log/Xorg.0.log \
     /var/lib/gdm3/.local/share/xorg/Xorg.0.log 2>/dev/null
sudo grep -E '\(EE\)' /var/log/Xorg.0.log | tail -20
```

- **`gdm` active, a `LoadModule: "dummy"` line in headless mode, no `(EE)` lines** →
  continue to Step 6.
- **`gdm` active but no dummy line while headless** → Xorg ignored the config or fell back.
  **Stop and fix:** confirm `xserver-xorg-video-dummy` is installed
  (`dpkg -l xserver-xorg-video-dummy`), then `sudo systemctl restart gdm`. Re-run Step 5.
- **`gdm` inactive** → **stop and fix:** `sudo systemctl restart gdm`, wait 15 s, re-run
  Step 5. If it will not stay up, `journalctl -u gdm -n 50 --no-pager`.
- **`(EE)` lines naming the dummy device** → the headless config is wrong for this unit.
  Roll back (`sudo ./scripts/rollback.sh --no-reboot`) to get the monitor config live, then
  fix `headless.conf` before re-enabling.

---

## Step 6 — Confirm the switch timing is behaving

Only relevant if switching happens but at the wrong time.

```bash
grep -E '^(POLL|PLUG_POLLS|UNPLUG_POLLS)=' /usr/local/sbin/display-mode.sh
journalctl -t display-mode --since '1 hour ago' --no-pager
```

- **Switches at ~10 s in and ~120 s out** → working as designed. Continue to Step 7.
- **Unit goes headless whenever somebody switches the monitor off** → expected: a monitor
  that drops its signal when powered off counts as unplugged. **Fix:** raise `UNPLUG_POLLS`
  in `/usr/local/sbin/display-mode.sh` *and* in this repo's `scripts/display-mode.sh`, then
  `sudo systemctl restart display-mode.service`.
- **Repeated switches, desktop logging out every couple of minutes** → detection is
  flapping. Go back to Step 2 and check the cable and monitor power before changing timings.

---

## Step 7 — Confirm AnyDesk

```bash
systemctl is-active anydesk
anydesk --get-id
sudo journalctl -u anydesk -n 50 --no-pager
```

- **Active, an ID printed, and a usable desktop from the client** → the unit is healthy.
  Record it in `UNIT-INVENTORY.md`.
- **Active, `--get-id` empty** → outbound TCP 443/6568 blocked. **Fix** the egress path,
  wait 60 s, re-run Step 7.
- **Inactive** → `sudo systemctl enable --now anydesk`, re-run Step 7.
- **Black screen, but Steps 4–5 passed** → AnyDesk is attached to the X server that was torn
  down by the last GDM restart. **Fix:** `sudo systemctl restart anydesk`, wait 10 s,
  reconnect.
- **Prompted to accept on the remote side** → no unattended password.
  `sudo ./scripts/install-anydesk.sh --set-password`.
- **GDM greeter instead of a desktop** → no autologin configured. That is stock behaviour;
  either type the account password over AnyDesk each reboot, or enable autologin in
  `/etc/gdm3/custom.conf` and accept that anyone with physical access gets a logged-in
  desktop. The validated build did not enable it.

---

## Last resort

```bash
sudo ./scripts/rollback.sh          # restores physical.conf, disables the service, reboots
```

After this the unit is back to its pre-install state — which, with no monitor attached,
means no usable remote desktop. Use it to get a clean base before re-running
[`06-new-unit-runbook.md`](06-new-unit-runbook.md) from Step 2, not as a fix.
