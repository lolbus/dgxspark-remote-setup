# Unit inventory

One row per physical unit. Update and commit whenever a unit is built, rebuilt, or moved.
**No unattended-access passwords here** — password manager, referenced by entry name.

| Hostname | OEM / model | Physical access | AnyDesk ID | Tailscale IP | Mode at rest | display-mode.service | Step 7 (live switch) | Last verified |
|---|---|---|---|---|---|---|---|---|
| `dxclabs-dgxspark` | Dell Pro Max GB10 | remote only | `1488388644` | `100.109.196.102` | headless | enabled | not run (no site access) | TO CONFIRM |
| `dxclabs-dgxspark-zgx-7701` | HP ZGX Nano GB10 | on-site | TO CONFIRM | TO CONFIRM | headless | enabled | TO CONFIRM | TO CONFIRM |

## Column meanings

- **Physical access** — `on-site` means Step 7 of the runbook (plug/unplug with
  `journalctl -t display-mode -f`) can be run. `remote only` means it cannot.
- **Mode at rest** — what the unit runs with nobody standing at it: `headless` or `physical`.
- **display-mode.service** — enabled on the unit, per `systemctl is-enabled`.
- **Step 7** — `passed`, or `not run` with the reason. Do not write `passed` for a unit
  where nobody plugged a monitor in.
- **Last verified** — date `scripts/healthcheck.sh` last exited 0 on that unit.

## Per-unit deviations

Record anything that differs from the stock procedure — most likely a raised `UNPLUG_POLLS`
where a monitor drops signal when powered off.

| Hostname | Deviation | Why |
|---|---|---|
| — | — | — |

## Adding a unit

1. Build it with `docs/06-new-unit-runbook.md`.
2. Run `./scripts/healthcheck.sh`; it prints every value this table needs.
3. Add the row, commit, push.
