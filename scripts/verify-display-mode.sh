#!/usr/bin/env bash
#
# verify-display-mode.sh — Step 7 of Manual-Direct-commands.txt, run as one command
# set, with the pass/stop branches from that document printed alongside.
# Read-only.

set -uo pipefail
DIR=/etc/X11/display-modes
XCONF=/etc/X11/xorg.conf

echo "=== switch log this boot (journalctl -t display-mode -b) ==="
journalctl -t display-mode -b --no-pager 2>/dev/null | tail -20 || echo "(none)"

echo
echo "=== which config is live ==="
if cmp -s "$DIR/headless.conf" "$XCONF"; then
    echo "XORG.CONF = HEADLESS"
    LIVE=headless
elif cmp -s "$DIR/physical.conf" "$XCONF"; then
    echo "XORG.CONF = PHYSICAL"
    LIVE=physical
else
    echo "XORG.CONF matches NEITHER variant — it has been hand-edited"
    LIVE=unknown
fi

echo
echo "=== did Xorg load the dummy driver ==="
grep -h 'LoadModule: "dummy"' /var/log/Xorg.0.log \
     /var/lib/gdm3/.local/share/xorg/Xorg.0.log 2>/dev/null || echo "(no dummy LoadModule line)"

echo
echo "=== monitor count as the switcher sees it ==="
nvidia-xconfig --query-gpu-info 2>/dev/null | grep -E "Number of Display Devices|EDID Name" || echo "(nvidia-xconfig returned nothing)"

echo
echo "=== services ==="
systemctl is-active display-mode gdm

cat <<BRANCHES

--- How to read this (Step 7 of Manual-Direct-commands.txt) ---
switched to headless + XORG.CONF = HEADLESS + a LoadModule: "dummy" line +
  active twice, and AnyDesk shows the login screen
      -> headless mode works. Continue to the live-switch test (Step 8).
switched to physical with no monitor attached
      -> stop. Paste this whole output.
headless, but gdm is not active, or AnyDesk is still black
      -> stop. Paste: systemctl status gdm --no-pager

Live-switch test (Step 8, needs someone at the unit):
      journalctl -t display-mode -f
  plug the monitor in   -> "switched to physical" within ~10 s
  unplug the monitor    -> "switched to headless" about 120 s later
  nothing within 30 s   -> Ctrl+C and run, with the monitor attached:
      sudo nvidia-xconfig --query-gpu-info | grep -E "Number of Display Devices|EDID Name"
BRANCHES

[[ "${LIVE}" == "unknown" ]] && exit 1 || exit 0
