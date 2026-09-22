#!/usr/bin/env bash
#
# rollback.sh — the Rollback line from Manual-Direct-commands.txt:
#
#   sudo systemctl disable --now display-mode.service \
#     && sudo cp /etc/X11/display-modes/physical.conf /etc/X11/xorg.conf \
#     && sudo reboot
#
# Returns the unit to its pre-install monitor config. On a unit with no monitor
# attached that means no usable remote desktop until you re-install.

set -euo pipefail
DIR=/etc/X11/display-modes
XCONF=/etc/X11/xorg.conf
DO_REBOOT=1

[[ "${1:-}" == "--no-reboot" ]] && DO_REBOOT=0
[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }

if [[ ! -s "$DIR/physical.conf" ]]; then
    echo "STOP: $DIR/physical.conf is missing. Nothing to roll back to." >&2
    echo "Restore a known-good xorg.conf by hand before rebooting." >&2
    exit 2
fi

systemctl disable --now display-mode.service || true
cp "$DIR/physical.conf" "$XCONF"
echo "restored $DIR/physical.conf -> $XCONF; display-mode.service disabled"

if (( DO_REBOOT )); then
    echo "rebooting in 5s (Ctrl+C to abort)"; sleep 5; reboot
else
    echo "not rebooting (--no-reboot). The new config takes effect on next boot."
fi
