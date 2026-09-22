# Changelog

All notable changes to this runbook. Newest first.

## 2026-09-22 — Initial

- First published runbook for headless AnyDesk on DGX Spark / GB10, Ubuntu 24.04 ARM64.
- Dummy Xorg screen (`xserver-xorg-video-dummy`) with hotplug switching to the unit's stock
  display config when a monitor is attached.
- Installer, health check and uninstall scripts; sequential troubleshooting tree.
- AnyDesk pinned to `8.0.4-1` arm64.
- Unit inventory seeded with `dxclabs-dgxspark` (Dell) and `dxclabs-dgxspark-zgx-7701` (HP ZGX).

### Known gaps

- Every `VERIFY-ON-UNIT` marker in `docs/` and `config/` is a value not yet confirmed against
  a live unit in this revision. The HP ZGX row in `UNIT-INVENTORY.md` is incomplete.
- The NVIDIA `ConnectedMonitor` + `CustomEDID` alternative in `docs/04` is documented but
  untested on GB10.
