# Changelog

Newest first.

## 2026-09-22 — Corrected to the validated procedure

The first published version of this repo did **not** document the solution that was built
and validated on `dxclabs-dgxspark`. It documented a plausible-looking reconstruction with a
different mechanism. It has been replaced.

Removed (invented, never run on a unit):

- `display-autoswitch.sh`, `display-autoswitch.service`, `99-drm-hotplug.rules` — a
  udev-hotplug switcher with a flat 4 s debounce.
- DRM sysfs monitor detection (`/sys/class/drm/card*-*/status`).
- `xorg.conf.dummy` with added modelines, a `Virtual` ceiling, `AutoAddGPU false` and DPMS
  overrides.
- The "empty physical variant means delete `/etc/X11/xorg.conf`" behaviour, which was wrong:
  DGX OS ships an `xorg.conf` and that file is what `physical.conf` is copied from.
- `60-disable-suspend-headless.conf` sleep masking.
- A three-option decision record in `docs/01` presenting reasoning that was never used.

Now in place, extracted verbatim from `Manual-Direct-commands.txt`:

- `scripts/display-mode.sh` — `boot` and `watch` subcommands, `POLL=5`, `PLUG_POLLS=2`
  (~10 s to physical), `UNPLUG_POLLS=24` (~120 s to headless), detection via
  `nvidia-xconfig --query-gpu-info`.
- `config/display-mode.service` — `ExecStartPre=... boot`, `ExecStart=... watch`,
  `Before=display-manager.service gdm.service`, `Restart=always`.
- `config/headless.conf` — dummy driver, `VideoRam 256000`, single 1920x1080 mode.
- `scripts/install-display-mode.sh` (manual Steps 1–5, with the `Driver "nvidia"` gate as a
  hard stop), `scripts/verify-display-mode.sh` (Step 7), `scripts/rollback.sh` (the
  Rollback line).
- All docs rewritten on the real mechanism, each carrying a provenance banner.

Still not validated on a unit, and labelled as such: `docs/03-anydesk-install.md`,
`scripts/install-anydesk.sh` (AnyDesk `8.0.4-1` arm64, from vendor documentation),
`scripts/preflight.sh`, `scripts/healthcheck.sh`.

Added `.gitattributes` so shell and config files stay LF; `Manual-Direct-commands.txt` is
marked binary-ish (`-text`) so its line endings are left alone.

## 2026-09-22 — Initial (superseded)

First published runbook. Mechanism was a reconstruction, not the deployed solution. See
above.
