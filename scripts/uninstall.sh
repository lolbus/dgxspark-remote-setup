#!/usr/bin/env bash
#
# uninstall.sh — back out the virtual-display + autoswitch changes.
# Leaves AnyDesk alone (remove it with: sudo apt-get purge anydesk).
#
# DESTRUCTIVE: restarts the display manager.

set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }

BACKUP_DIR="/var/backups/dgx-virtualscreen"
say() { printf '\n>> %s\n' "$*"; }

say "Disabling the autoswitch"
systemctl disable --now display-autoswitch.service >/dev/null 2>&1 || true
rm -f /etc/systemd/system/display-autoswitch.service
rm -f /etc/udev/rules.d/99-drm-hotplug.rules
rm -f /usr/local/sbin/display-autoswitch.sh
rm -f /run/display-autoswitch.state
systemctl daemon-reload
udevadm control --reload-rules

say "Restoring Xorg config"
if [[ -s "$BACKUP_DIR/etc_X11_xorg.conf" ]]; then
    install -m 0644 "$BACKUP_DIR/etc_X11_xorg.conf" /etc/X11/xorg.conf
    echo "   restored the unit's original /etc/X11/xorg.conf"
else
    rm -f /etc/X11/xorg.conf
    echo "   removed /etc/X11/xorg.conf (stock auto-detect)"
fi
rm -rf /etc/X11/autoswitch

say "Restoring GDM config"
if [[ -s "$BACKUP_DIR/etc_gdm3_custom.conf" ]]; then
    install -m 0644 "$BACKUP_DIR/etc_gdm3_custom.conf" /etc/gdm3/custom.conf
    echo "   restored original custom.conf (Wayland setting reverts too)"
else
    echo "   no backup found; leaving /etc/gdm3/custom.conf as is"
fi

say "Unmasking sleep targets"
systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1 || true
rm -f /etc/systemd/sleep.conf.d/60-disable-suspend-headless.conf

say "DESTRUCTIVE: restarting the display manager"
systemctl restart display-manager.service || true
echo "Done. AnyDesk was left installed."
