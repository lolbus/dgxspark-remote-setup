#!/usr/bin/env bash
#
# install-anydesk.sh — AnyDesk arm64 install + unattended access on a headless unit.
# Idempotent: re-running upgrades the package and leaves an existing password alone
# unless --set-password is given.
#
# AnyDesk publishes arm64 .deb packages under download.anydesk.com/rpi/ (the /rpi/
# path is historical; the package is plain arm64 and installs on Ubuntu 24.04 ARM64).

set -euo pipefail

ANYDESK_VERSION="${ANYDESK_VERSION:-8.0.4-1}"
ANYDESK_URL="${ANYDESK_URL:-https://download.anydesk.com/rpi/anydesk_${ANYDESK_VERSION}_arm64.deb}"
WORKDIR="$(mktemp -d)"
SET_PASSWORD=0
PASSWORD=""
OPEN_FIREWALL=0

trap 'rm -rf "$WORKDIR"' EXIT

usage() {
    cat <<'USAGE'
Usage: sudo ./install-anydesk.sh [options]

  --set-password         Prompt for and set the unattended-access password.
  --password-stdin       Read the unattended-access password from stdin
                         (use this in automation; nothing lands in shell history).
  --open-firewall        Add a UFW rule for TCP 7070 (AnyDesk direct/LAN connections).
  --version X.Y.Z-1      Install a specific AnyDesk version. Default: 8.0.4-1
  -h, --help
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --set-password)   SET_PASSWORD=1 ;;
        --password-stdin) SET_PASSWORD=1; PASSWORD="$(cat)" ;;
        --open-firewall)  OPEN_FIREWALL=1 ;;
        --version)        ANYDESK_VERSION="${2:?--version needs a value}"
                          ANYDESK_URL="https://download.anydesk.com/rpi/anydesk_${ANYDESK_VERSION}_arm64.deb"
                          shift ;;
        -h|--help)        usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
say() { printf '\n>> %s\n' "$*"; }

# A Wayland session cannot be captured by AnyDesk. Fail loudly rather than
# leaving someone to debug a black screen later.
say "Checking the display stack is X11"
if grep -qiE '^[[:space:]]*WaylandEnable[[:space:]]*=[[:space:]]*false' /etc/gdm3/custom.conf 2>/dev/null; then
    echo "   OK: GDM is pinned to X11"
else
    echo "   REFUSING: GDM is not pinned to X11. Run install-virtual-display.sh first." >&2
    exit 2
fi

say "Downloading AnyDesk $ANYDESK_VERSION (arm64)"
echo "   $ANYDESK_URL"
curl -fsSL --retry 3 -o "$WORKDIR/anydesk.deb" "$ANYDESK_URL"
ls -lh "$WORKDIR/anydesk.deb" | sed 's/^/   /'

say "Installing"
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq "$WORKDIR/anydesk.deb"

say "Enabling the service"
systemctl enable --now anydesk >/dev/null 2>&1 || systemctl restart anydesk || true
sleep 3
systemctl is-active anydesk | sed 's/^/   service: /'

if (( SET_PASSWORD )); then
    say "Setting the unattended-access password"
    if [[ -z "$PASSWORD" ]]; then
        read -r -s -p "   unattended password: " PASSWORD; echo
        read -r -s -p "   repeat:              " P2; echo
        [[ "$PASSWORD" == "$P2" ]] || { echo "   passwords differ" >&2; exit 1; }
    fi
    [[ ${#PASSWORD} -ge 12 ]] || echo "   WARNING: short password on an internet-reachable ID"
    printf '%s' "$PASSWORD" | anydesk --set-password
    unset PASSWORD P2
    echo "   set. Record it in the team password manager, NOT in this repo."
else
    echo
    echo ">> No password set. Until one is, unattended access will not work."
    echo "   Set it with:  sudo ./scripts/install-anydesk.sh --set-password"
fi

if (( OPEN_FIREWALL )) && command -v ufw >/dev/null; then
    say "Opening TCP 7070 for AnyDesk direct connections"
    ufw allow 7070/tcp comment 'AnyDesk direct' >/dev/null || true
    ufw status | grep -i 7070 | sed 's/^/   /' || true
fi

say "This unit's AnyDesk ID"
ID="$(anydesk --get-id 2>/dev/null || echo 'unavailable')"
echo "   ID: $ID"
echo "   Alias: $(anydesk --get-alias 2>/dev/null || echo 'none')"
echo
echo "Add the ID to UNIT-INVENTORY.md and commit."
