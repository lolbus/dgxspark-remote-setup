# 06 — New unit runbook (the fast path)

Target: a factory-fresh or reimaged GB10 unit, remote-capable via AnyDesk, in about 15
minutes. Every step is run **over SSH**. Nothing here is done over AnyDesk, because two of
the steps restart the display manager and would cut your own session.

If a step fails, stop and go to [`08-troubleshooting.md`](08-troubleshooting.md). Do not
continue past a failed step hoping a later one fixes it.

**Rollback, at any point from Step 3 onwards:**

```bash
sudo ./scripts/uninstall.sh      # DESTRUCTIVE: restarts the display manager
```

It restores the unit's original `/etc/X11/xorg.conf` and `/etc/gdm3/custom.conf` from
`/var/backups/dgx-virtualscreen/`, removes the switcher and unmasks the sleep targets.
AnyDesk is left installed. This returns the unit to stock — on a headless box that means
no usable remote desktop, so it is how you get a clean base to re-run from, not a fix.

---

## Step 0 — Establish the recovery channel (before anything else)

```bash
ssh <admin>@<unit-address>
sudo systemctl enable --now ssh
sudo tailscale up            # if this unit joins the tailnet
tailscale ip -4
```

Write the Tailscale IP into `UNIT-INVENTORY.md` now, not later. Everything after this point
can break the display; SSH is how you get back.

## Step 1 — Get the repo onto the unit

```bash
git clone <this-repo-url> ~/dgx-virtualscreen
cd ~/dgx-virtualscreen
```

No git access on the unit? From your machine: `scp -r <repo-dir> <admin>@<unit>:~/dgx-virtualscreen`

## Step 2 — Survey (changes nothing)

```bash
sudo ./scripts/preflight.sh
```

Read the `DRM connectors` block and the `Blocking conditions` block.

- Exit 0, and every connector `disconnected` → normal headless unit. Continue to Step 3.
- Exit 0, and one connector `connected` with nothing physically plugged in → a phantom
  connector. Note its name; you may need it in Step 6. Continue to Step 3.
- Exit 1 (`BLOCKER: no active SSH server`) → **stop**. Fix SSH, then re-run Step 2.

Keep the output; paste it into the unit's build record.

## Step 3 — Install the virtual display and the switcher

DESTRUCTIVE: restarts the display manager.

```bash
sudo ./scripts/install-virtual-display.sh --autologin <admin-username>
```

Drop `--autologin` only if this unit must show the GDM greeter on every reboot and somebody
will type the account password remotely each time.

The script ends by printing `current_mode=`.

- On a headless unit it must say `dummy` → continue to Step 4.
- It says `physical` on a unit with no monitor → phantom connector.
  [`08-troubleshooting.md`](08-troubleshooting.md) Step 2.
- The script aborted, or SSH survived but the unit is otherwise wedged → roll back with
  `sudo ./scripts/uninstall.sh`, then diagnose before re-running Step 3.

## Step 4 — Install AnyDesk and set unattended access

```bash
sudo ./scripts/install-anydesk.sh --set-password --open-firewall
```

Drop `--open-firewall` if UFW is not in use on this unit. The script prints the AnyDesk ID at
the end — copy it now.

## Step 5 — Verify

```bash
./scripts/healthcheck.sh
```

- Exit 0 → the unit is built. Go to Step 6.
- Exit 1 → go to [`08-troubleshooting.md`](08-troubleshooting.md), Step 1, and work down.

Then connect from your own machine's AnyDesk client using the printed ID and the unattended
password. You should land on a 1920x1080 desktop. A black screen at this point means Step 5
passed but capture did not — [`08-troubleshooting.md`](08-troubleshooting.md) Step 5.

## Step 6 — Reboot test (do not skip)

The whole point is that the unit comes back alone after a power event.

```bash
sudo reboot
# wait ~90s
ssh <admin>@<unit-address> './dgx-virtualscreen/scripts/healthcheck.sh'
```

- Exit 0 and AnyDesk reconnects without anyone touching the unit → done.
- Exit 0 but AnyDesk shows the GDM greeter → autologin did not take. Re-run Step 3 with
  `--autologin`, then repeat Step 6.
- Exit 1 → the boot-time switcher did not run. [`08-troubleshooting.md`](08-troubleshooting.md)
  Step 3.

## Step 7 — Record the unit

Add a row to [`../UNIT-INVENTORY.md`](../UNIT-INVENTORY.md) with hostname, OEM, physical
access, AnyDesk ID, Tailscale IP, mode at rest, and today's date as `Last verified`. Commit
and push. Store the unattended password in the team password manager — not in the repo.

---

## One-page command summary

```bash
ssh <admin>@<unit>
sudo systemctl enable --now ssh && tailscale ip -4
git clone <repo-url> ~/dgx-virtualscreen && cd ~/dgx-virtualscreen
sudo ./scripts/preflight.sh
sudo ./scripts/install-virtual-display.sh --autologin <admin>
sudo ./scripts/install-anydesk.sh --set-password --open-firewall
./scripts/healthcheck.sh
sudo reboot

# rollback, if the unit needs to go back to stock
sudo ./scripts/uninstall.sh
```
