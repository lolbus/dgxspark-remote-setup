# 06 — New unit runbook

> **Provenance.** These are Steps 1–8 of
> [`../Manual-Direct-commands.txt`](../Manual-Direct-commands.txt), the procedure validated
> on `dxclabs-dgxspark`, with the file installs wrapped in a script. The manual file remains
> the source of truth — if you prefer to run the commands by hand, run them from there.

Run everything over **SSH**. Every mode switch restarts GDM, so an AnyDesk session is not a
safe place to do this from.

If a step fails, stop and go to [`08-troubleshooting.md`](08-troubleshooting.md). Do not
continue past a failed step.

**Rollback, at any point after Step 3:**

```bash
sudo ./scripts/rollback.sh              # restores physical.conf, disables the service, reboots
sudo ./scripts/rollback.sh --no-reboot  # same, without the reboot
```

---

## Step 0 — Recovery channel

```bash
ssh <admin>@<unit-address>
sudo systemctl enable --now ssh
sudo tailscale up          # if this unit joins the tailnet
tailscale ip -4
```

Record the Tailscale IP in `UNIT-INVENTORY.md` now.

## Step 1 — Repo onto the unit

```bash
git clone <this-repo-url> ~/dgx-display-mode && cd ~/dgx-display-mode
```

No git on the unit? `scp -r <repo-dir> <admin>@<unit>:~/dgx-display-mode`

## Step 2 — Survey (changes nothing)

```bash
sudo ./scripts/preflight.sh
```

- Exit 0 → continue to Step 3.
- `BLOCKER: no active SSH server` → stop, fix SSH, re-run.
- `BLOCKER: nvidia-xconfig missing` → stop. The switcher cannot detect monitors without it
  and would pin the unit to headless forever.
- `BLOCKER: no /etc/X11/xorg.conf` → stop. There is nothing to save as `physical.conf`.
  Generate one with a monitor attached (`sudo nvidia-xconfig`), confirm the desktop works on
  that monitor, then re-run.

## Step 3 — Install (manual Steps 1–5)

```bash
sudo ./scripts/install-display-mode.sh
```

This installs `xserver-xorg-video-dummy`, copies the unit's `xorg.conf` to
`physical.conf`, writes `headless.conf`, installs `display-mode.sh` and
`display-mode.service`, and enables the service.

**Nothing switches yet.** That is deliberate — the boot path is what Step 5 tests.

- Script prints the `Driver "nvidia"` line and finishes → continue to Step 4.
- `STOP: physical.conf does not declare Driver "nvidia"` → stop and paste the Driver lines.
  Do not force past this.

## Step 4 — Unplug the monitor, reboot (manual Step 6)

```bash
sudo reboot
```

Unplug any attached monitor first. This tests the headless path — with a monitor attached
the unit would boot into physical mode and prove nothing about remote access.

## Step 5 — Verify headless (manual Step 7)

SSH back in, then:

```bash
./scripts/verify-display-mode.sh
```

- `switched to headless`, `XORG.CONF = HEADLESS`, a `LoadModule: "dummy"` line, `active`
  twice, and AnyDesk shows the login screen → continue to Step 6.
- `switched to physical` with no monitor attached → stop, paste the whole output.
- Headless, but `gdm` not active or AnyDesk still black → stop, paste
  `systemctl status gdm --no-pager`.

## Step 6 — Install AnyDesk

```bash
sudo ./scripts/install-anydesk.sh --set-password --open-firewall
```

Drop `--open-firewall` if UFW is not in use. The script prints the AnyDesk ID — copy it.

Skip this step if AnyDesk is already installed and registered on the unit; check with
`anydesk --get-id`.

## Step 7 — Live switch test (manual Step 8, needs someone at the unit)

```bash
journalctl -t display-mode -f
```

- Plug the monitor in → `switched to physical` within ~10 s, login screen on the monitor.
- Nothing within 30 s → Ctrl+C, then with the monitor attached run
  `sudo nvidia-xconfig --query-gpu-info | grep -E "Number of Display Devices|EDID Name"`
  and paste it.
- Unplug the monitor → `switched to headless` about 120 s later, AnyDesk works again.

On a remote-only unit this step cannot be run. Record that in `UNIT-INVENTORY.md` rather
than marking it passed.

## Step 8 — Record the unit

```bash
./scripts/healthcheck.sh
```

Add a row to [`../UNIT-INVENTORY.md`](../UNIT-INVENTORY.md) — hostname, OEM, physical
access, AnyDesk ID, Tailscale IP, mode at rest, whether Step 7 was run, today's date.
Commit and push. Password goes in the password manager, not the repo.

---

## One-page summary

```bash
ssh <admin>@<unit>
sudo systemctl enable --now ssh && tailscale ip -4
git clone <repo-url> ~/dgx-display-mode && cd ~/dgx-display-mode
sudo ./scripts/preflight.sh
sudo ./scripts/install-display-mode.sh
# unplug monitor
sudo reboot
# ssh back in
./scripts/verify-display-mode.sh
sudo ./scripts/install-anydesk.sh --set-password --open-firewall
./scripts/healthcheck.sh

# rollback
sudo ./scripts/rollback.sh
```
