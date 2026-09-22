#!/usr/bin/env bash
#
# install-display-mode.sh
#
# Automates Steps 1-5 of Manual-Direct-commands.txt, which is the validated
# procedure from the original build of dxclabs-dgxspark. It installs files only.
# Nothing switches until you reboot (Step 6) — this matches the manual procedure
# deliberately: the boot path is what gets tested first.
#
# Run over SSH.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR=/etc/X11/display-modes
XCONF=/etc/X11/xorg.conf

[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
say() { printf '\n>> %s\n' "$*"; }

# ---- Step 1: the dummy driver ----------------------------------------------
say "Step 1: installing the Xorg fake-screen driver (xserver-xorg-video-dummy)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq xserver-xorg-video-dummy

# ---- Step 2: capture this unit's working monitor config ---------------------
say "Step 2: saving the current xorg.conf as the monitor-mode config"
if [[ ! -s "$XCONF" ]]; then
    cat >&2 <<'ERR'
   STOP: /etc/X11/xorg.conf does not exist on this unit.

   The validated procedure assumes DGX OS ships an xorg.conf that drives a real
   monitor, and copies it to physical.conf. Without it there is nothing to
   switch back to. Do not improvise a replacement — capture a known-good config
   from a unit that has one, or generate it with:
       sudo nvidia-xconfig
   with a monitor attached, verify the desktop works on the monitor, then re-run.
ERR
    exit 2
fi
mkdir -p "$DIR"
cp -p "$XCONF" "$DIR/physical.conf"
echo "   $XCONF -> $DIR/physical.conf"
if grep -q 'Driver.*"nvidia"' "$DIR/physical.conf"; then
    grep -n 'Driver' "$DIR/physical.conf" | sed 's/^/   /'
else
    cat >&2 <<'ERR'
   STOP: physical.conf does not declare Driver "nvidia".

   Step 2 of the manual procedure requires this check to pass before continuing.
   Paste the Driver lines printed above and stop here.
ERR
    grep -n 'Driver' "$DIR/physical.conf" | sed 's/^/   /' >&2 || true
    exit 2
fi

# ---- Step 3: the headless config -------------------------------------------
say "Step 3: installing the headless (dummy screen) config"
install -m 0644 "$REPO_DIR/config/headless.conf" "$DIR/headless.conf"
echo "   $DIR/headless.conf"

# ---- Step 4: the switch script ---------------------------------------------
say "Step 4: installing the switch script"
install -m 0755 "$REPO_DIR/scripts/display-mode.sh" /usr/local/sbin/display-mode.sh
grep -nE '^(POLL|PLUG_POLLS|UNPLUG_POLLS)=' /usr/local/sbin/display-mode.sh | sed 's/^/   /'

# ---- Step 5: the service ----------------------------------------------------
say "Step 5: installing and enabling the service"
install -m 0644 "$REPO_DIR/config/display-mode.service" /etc/systemd/system/display-mode.service
systemctl daemon-reload
systemctl enable display-mode.service
echo "   enabled (not started — the boot path is what Step 6 tests)"

cat <<'NEXT'

>> Installed. Nothing has switched yet.

Next, per Step 6 of the manual procedure:
  1. Unplug the monitor (if one is attached).
  2. sudo reboot
  3. SSH back in and run: ./scripts/verify-display-mode.sh

Rolling back before rebooting:  sudo ./scripts/rollback.sh --no-reboot
NEXT
