# 08 — Troubleshooting

Work this from **Step 1 downwards**. Each step ends with branches: one tells you to stop and
apply a fix, the other tells you to continue. Do not jump to the step whose title matches
your symptom — the earlier steps rule out the causes that make later diagnosis misleading.

Everything here is run over SSH.

---

## Step 1 — Confirm you still have a way back in

```bash
systemctl is-active ssh || systemctl is-active sshd
tailscale ip -4 2>/dev/null
```

- **Result: `active` and an IP printed** → you can safely restart the display stack.
  Continue to Step 2.
- **Result: inactive, or no route** → **stop.** Restore SSH first (`sudo systemctl enable
  --now ssh`, check UFW allows 22/tcp on the relevant interface). Do not run any command
  below this line until this passes; several of them restart the display manager.

---

## Step 2 — Confirm what the kernel sees

```bash
grep -H . /sys/class/drm/card*-*/status
```

- **Result: every connector `disconnected`, no monitor attached** → expected headless state.
  Continue to Step 3.
- **Result: a connector reports `connected` and nothing is physically plugged in** → a
  phantom connector is pinning the unit into physical mode. **Stop here and fix:** add that
  connector's name to the exclusion `case` in `physical_connector()` in
  `scripts/display-autoswitch.sh`, reinstall it
  (`sudo install -m 0755 scripts/display-autoswitch.sh /usr/local/sbin/display-autoswitch.sh`),
  then `sudo /usr/local/sbin/display-autoswitch.sh --force`. Re-run Step 2.
- **Result: no files matched at all** → the DRM subsystem is not exposing connectors.
  **Stop here and fix:** check `cat /sys/module/nvidia_drm/parameters/modeset` returns `Y`;
  if it returns `N`, set `nvidia-drm.modeset=1` on the kernel command line, reboot, and
  re-run Step 2. VERIFY-ON-UNIT: the parameter name differs on some DGX OS builds.

---

## Step 3 — Confirm the switcher ran and agreed with Step 2

```bash
/usr/local/sbin/display-autoswitch.sh --status
sudo tail -40 /var/log/display-autoswitch.log
```

- **Result: `desired_mode` equals `current_mode`, and it matches Step 2** (no monitor →
  `dummy`) → the switcher is correct. Continue to Step 4.
- **Result: the modes disagree, and the log shows no recent entry** → the switcher never
  ran. **Stop here and fix:** `sudo systemctl start display-autoswitch.service`, then
  `systemctl status display-autoswitch.service`. Re-run Step 3.
- **Result: the log shows `FATAL: ... missing or empty`** → the variant files are not
  installed. **Stop here and fix:** re-run `sudo ./scripts/install-virtual-display.sh`.
  Re-run Step 3.
- **Result: the modes agree but are the wrong way round** (headless unit in `physical`) →
  you are in the Step 2 phantom-connector case. Go back to Step 2.

---

## Step 4 — Confirm hotplug switching will work (skip on a permanently headless unit)

```bash
sudo udevadm trigger --subsystem-match=drm --action=change
sudo journalctl -u display-autoswitch.service -n 20 --no-pager
```

- **Result: the unit ran within a few seconds** → hotplug wiring is good. Continue to Step 5.
- **Result: nothing ran** → the udev rule is not loaded. **Stop here and fix:** confirm
  `/etc/udev/rules.d/99-drm-hotplug.rules` exists, then
  `sudo udevadm control --reload-rules && sudo udevadm trigger`. Re-run Step 4.
- **Result: it ran but errored** → read the error in `journalctl`; it is a script problem,
  not a udev problem. Continue to Step 5 only after the unit exits 0.

---

## Step 5 — Confirm an X server exists with a real mode

```bash
systemctl is-active display-manager.service
pgrep -a Xorg
XAUTH=$(sudo find /run/user -maxdepth 3 -name 'Xauthority' | head -1)
sudo DISPLAY=:0 XAUTHORITY="$XAUTH" xrandr | head
```

- **Result: display-manager active, an Xorg process, and `xrandr` lists a mode with `*`** →
  the screen exists. Continue to Step 6.
- **Result: display-manager active but no Xorg process** → X is crashing at startup.
  **Stop here and fix:** `sudo grep -E '\(EE\)' /var/log/Xorg.0.log | tail -20`. The usual
  cause is a bad modeline or `Virtual` smaller than the largest mode in
  `/etc/X11/autoswitch/xorg.conf.dummy`. Fix the variant, reinstall it, re-run Step 5.
- **Result: Xorg running but `xrandr` shows no `*` mode** → the dummy screen has no active
  mode. **Stop here and fix:** `sudo DISPLAY=:0 XAUTHORITY="$XAUTH" xrandr -s 1920x1080`.
  If that fails, the modelines in the dummy config are wrong — regenerate with
  `cvt 1920 1080 60`. Re-run Step 5.
- **Result: display-manager inactive** → **stop here and fix:**
  `sudo systemctl restart display-manager.service`, wait 10s, re-run Step 5. If it will not
  stay up, `journalctl -u display-manager -n 50 --no-pager`.

---

## Step 6 — Confirm the session is X11, not Wayland

```bash
grep -iE 'WaylandEnable' /etc/gdm3/custom.conf
loginctl list-sessions
loginctl show-session <id> -p Type
```

- **Result: `WaylandEnable=false` and session `Type=x11`** → capture will work. Continue to
  Step 7.
- **Result: `Type=wayland`, or WaylandEnable is absent/commented** → this is the cause of
  `Display server is not supported` and of most black screens. **Stop here and fix:** set
  `WaylandEnable=false` in `/etc/gdm3/custom.conf` under `[daemon]`, then
  `sudo systemctl restart display-manager.service`. Wait 15s, re-run Step 6.
- **Result: `WaylandEnable=false` but the session is still wayland** → an AccountsService
  override is forcing it. **Stop here and fix:** check
  `/var/lib/AccountsService/users/<username>` for an `XSession=` line and set it to
  `ubuntu-xorg` (VERIFY-ON-UNIT: the session name on this Ubuntu build — list them with
  `ls /usr/share/xsessions/`). Restart the display manager, re-run Step 6.

---

## Step 7 — Confirm AnyDesk is registered and attached

```bash
systemctl is-active anydesk
anydesk --get-id
sudo journalctl -u anydesk -n 50 --no-pager
```

- **Result: active, and an ID is printed** → the unit is reachable. Continue to Step 8.
- **Result: active, but `--get-id` prints nothing** → the unit cannot reach AnyDesk's
  network. **Stop here and fix:** confirm outbound TCP 443 and 6568 are permitted from this
  unit (proxy, UFW, corporate egress). Re-run Step 7 after 60s.
- **Result: inactive** → **stop here and fix:** `sudo systemctl enable --now anydesk`, then
  `journalctl -u anydesk -n 50`. Re-run Step 7.

---

## Step 8 — Confirm what the client actually sees

Connect with the AnyDesk client from another machine.

- **Result: a usable desktop** → the unit is healthy; record it in `UNIT-INVENTORY.md`.
- **Result: prompted to accept on the remote side** → no unattended password is set.
  **Fix:** `sudo ./scripts/install-anydesk.sh --set-password`.
- **Result: the GDM greeter instead of a desktop** → autologin is not enabled. **Fix:**
  `sudo ./scripts/install-virtual-display.sh --autologin <user>` and reboot. Harmless if you
  are content to type the account password remotely each reboot.
- **Result: black screen, but Steps 5–7 all passed** → AnyDesk is attached to a stale X
  server. **Fix:** `sudo systemctl restart anydesk`, wait 10s, reconnect. If it recurs after
  every display-manager restart, add an `After=display-manager.service` drop-in to the
  anydesk unit.
- **Result: desktop appears then the session drops every ~30 s** → the display manager is
  restarting in a loop, almost always because the switcher is flapping between modes.
  **Fix:** go back to Step 2; a phantom connector toggling state is the usual cause. Raise
  `DEBOUNCE_SECONDS` via a systemd drop-in if the connector genuinely flaps.
- **Result: screen is 640x480 or similarly tiny** → X fell back to a default mode. Go back
  to Step 5, third branch.

---

## Last resort

```bash
sudo ./scripts/uninstall.sh      # DESTRUCTIVE: restarts the display manager
```

This restores the unit's original `/etc/X11/xorg.conf` and `/etc/gdm3/custom.conf` from
`/var/backups/dgx-virtualscreen/`, removes the switcher, and unmasks the sleep targets.
AnyDesk is left installed. After this the unit is back to stock behaviour — which, on a
headless box, means no usable remote desktop. Use it to get a clean base before re-running
the runbook, not as a fix.
