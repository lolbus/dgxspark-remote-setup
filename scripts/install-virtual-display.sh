#!/usr/bin/env bash
#
# install-virtual-display.sh — dummy Xorg screen + hotplug autoswitch + X11 forcing.
# Idempotent: safe to re-run. Every file it overwrites is backed up once to
# /var/backups/dgx-virtualscreen/.
#
# DESTRUCTIVE: restarts the display manager at the end unless --no-restart.
# Run over SSH, never over AnyDesk.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VARIANT_DIR="/etc/X11/autoswitch"
BACKUP_DIR="/var/backups/dgx-virtualscreen"
AUTOLOGIN_USER=""
DO_RESTART=1
DISABLE_SLEEP=1
DISABLE_IDLE=1

usage() {
    cat <<'USAGE'
Usage: sudo ./install-virtual-display.sh [options]

  --autologin USER   Enable GDM automatic login for USER so the unit reaches a
                     full desktop after reboot without anyone typing a password.
                     Without this you land on the GDM greeter over AnyDesk and
                     must type the account password on every reboot.
  --no-restart       Install everything but do not restart the display manager.
  --keep-sleep       Do not mask suspend/hibernate targets.
  --keep-idle        Do not disable GNOME screen blanking / lock.
  -h, --help
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --autologin)  AUTOLOGIN_USER="${2:?--autologin needs a username}"; shift ;;
        --no-restart) DO_RESTART=0 ;;
        --keep-sleep) DISABLE_SLEEP=0 ;;
        --keep-idle)  DISABLE_IDLE=0 ;;
        -h|--help)    usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }

say() { printf '\n>> %s\n' "$*"; }

backup_once() {
    local f="$1"
    [[ -e "$f" ]] || return 0
    mkdir -p "$BACKUP_DIR"
    local dest="$BACKUP_DIR/$(echo "${f#/}" | tr '/' '_')"
    [[ -e "$dest" ]] || { cp -a "$f" "$dest"; echo "   backed up $f -> $dest"; }
}

# ---------------------------------------------------------------- 1. packages
say "Installing the software framebuffer driver (xserver-xorg-video-dummy)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq xserver-xorg-video-dummy x11-xserver-utils

# ------------------------------------------------------------ 2. Xorg variants
say "Installing Xorg config variants into $VARIANT_DIR"
install -d -m 0755 "$VARIANT_DIR"
install -m 0644 "$REPO_DIR/config/xorg.conf.dummy" "$VARIANT_DIR/xorg.conf.dummy"

if [[ ! -e "$VARIANT_DIR/xorg.conf.physical" ]]; then
    if [[ -s /etc/X11/xorg.conf ]] && ! cmp -s /etc/X11/xorg.conf "$VARIANT_DIR/xorg.conf.dummy"; then
        backup_once /etc/X11/xorg.conf
        cp -a /etc/X11/xorg.conf "$VARIANT_DIR/xorg.conf.physical"
        echo "   captured this unit's existing xorg.conf as the physical variant"
    else
        : > "$VARIANT_DIR/xorg.conf.physical"
        echo "   physical variant is EMPTY = stock Xorg auto-detect (normal on DGX Spark)"
    fi
    chmod 0644 "$VARIANT_DIR/xorg.conf.physical"
else
    echo "   physical variant already present; left untouched"
fi

# ------------------------------------------------------------- 3. the switcher
say "Installing the switcher, its systemd unit and the hotplug rule"
install -m 0755 "$REPO_DIR/scripts/display-autoswitch.sh" /usr/local/sbin/display-autoswitch.sh
install -m 0644 "$REPO_DIR/config/display-autoswitch.service" /etc/systemd/system/display-autoswitch.service
install -m 0644 "$REPO_DIR/config/99-drm-hotplug.rules" /etc/udev/rules.d/99-drm-hotplug.rules
systemctl daemon-reload
udevadm control --reload-rules
systemctl enable display-autoswitch.service >/dev/null

# ------------------------------------------------------------ 4. force X11/GDM
say "Forcing X11 (AnyDesk cannot capture a Wayland session)"
if [[ -f /etc/gdm3/custom.conf ]]; then
    backup_once /etc/gdm3/custom.conf
    if grep -qE '^[[:space:]]*#?[[:space:]]*WaylandEnable' /etc/gdm3/custom.conf; then
        sed -i -E 's|^[[:space:]]*#?[[:space:]]*WaylandEnable[[:space:]]*=.*|WaylandEnable=false|' /etc/gdm3/custom.conf
    else
        sed -i -E 's|^\[daemon\]|[daemon]\nWaylandEnable=false|' /etc/gdm3/custom.conf
    fi
    grep -E '^WaylandEnable' /etc/gdm3/custom.conf | sed 's/^/   /'
else
    echo "   WARNING: /etc/gdm3/custom.conf not found — VERIFY-ON-UNIT which display manager runs"
fi

if [[ -n "$AUTOLOGIN_USER" ]]; then
    say "Enabling GDM automatic login for '$AUTOLOGIN_USER'"
    id "$AUTOLOGIN_USER" >/dev/null || { echo "no such user" >&2; exit 1; }
    sed -i -E '/^[[:space:]]*#?[[:space:]]*AutomaticLogin(Enable)?[[:space:]]*=/d' /etc/gdm3/custom.conf
    sed -i -E "s|^\[daemon\]|[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=$AUTOLOGIN_USER|" /etc/gdm3/custom.conf
    echo "   NOTE: anyone with physical access now gets a logged-in desktop."
    echo "         The AnyDesk unattended password becomes the only remote barrier."
fi

# ------------------------------------------------- 5. keep the unit reachable
if (( DISABLE_SLEEP )); then
    say "Masking suspend/hibernate (a suspended remote-only unit is unreachable)"
    install -d -m 0755 /etc/systemd/sleep.conf.d
    install -m 0644 "$REPO_DIR/config/60-disable-suspend-headless.conf" \
        /etc/systemd/sleep.conf.d/60-disable-suspend-headless.conf
    systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1 || true
fi

if (( DISABLE_IDLE )) && [[ -n "$AUTOLOGIN_USER" ]]; then
    say "Disabling GNOME idle blanking and screen lock for '$AUTOLOGIN_USER'"
    # Applies to the user's dconf profile; takes effect on their next session.
    sudo -u "$AUTOLOGIN_USER" dbus-run-session -- bash -c '
        gsettings set org.gnome.desktop.session idle-delay "uint32 0"
        gsettings set org.gnome.desktop.screensaver lock-enabled false
        gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type "nothing"
    ' 2>/dev/null || echo "   WARNING: gsettings did not apply; set it inside the desktop session instead"
fi

# ------------------------------------------------------------ 6. first switch
say "Running the switcher once to pick the mode that matches right now"
if (( DO_RESTART )); then
    /usr/local/sbin/display-autoswitch.sh --force
else
    /usr/local/sbin/display-autoswitch.sh --force --boot
fi

if (( DO_RESTART )); then
    say "DESTRUCTIVE: restarting the display manager"
    systemctl restart display-manager.service || true
    sleep 5
fi

say "Done. Current state:"
/usr/local/sbin/display-autoswitch.sh --status | sed 's/^/   /'
echo
echo "Next: sudo ./scripts/install-anydesk.sh"
