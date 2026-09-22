# Unit inventory

One row per physical unit. Update and commit whenever a unit is built, rebuilt, or moved.
**Do not record unattended-access passwords here** — store those in the team password manager
and reference them by entry name only.

| Hostname | OEM / model | Physical access | AnyDesk ID | AnyDesk alias | Tailscale IP | Display mode at rest | Autoswitch installed | Last verified |
|---|---|---|---|---|---|---|---|---|
| `dxclabs-dgxspark` | Dell Pro Max GB10 | remote only | `1488388644` | — | `100.109.196.102` | dummy (no monitor) | yes | VERIFY-ON-UNIT |
| `dxclabs-dgxspark-zgx-7701` | HP ZGX Nano GB10 | on-site | VERIFY-ON-UNIT | — | VERIFY-ON-UNIT | dummy (no monitor) | yes | VERIFY-ON-UNIT |

## Column meanings

- **Physical access** — `on-site` means a hardware EDID emulator plug is an option for that
  unit; `remote only` means the software virtual screen is the only route.
- **Display mode at rest** — what the unit runs with nobody standing at it: `dummy` or
  `physical`.
- **Autoswitch installed** — whether `display-autoswitch.service` is enabled on the unit.
- **Last verified** — date `scripts/healthcheck.sh` last exited 0 on that unit.

## Adding a unit

1. Build it with `docs/06-new-unit-runbook.md`.
2. Run `./scripts/healthcheck.sh`; it prints every value this table needs.
3. Add the row, commit, push.
