#!/usr/bin/env bash
#
# healthcheck.sh — one screen of state for a DGX Spark virtual-display + AnyDesk unit.
# Read-only. Exit 0 = every hard check passed. Exit 1 = at least one FAIL.
# The values it prints are exactly the columns UNIT-INVENTORY.md wants.

set -uo pipefail

PASS=0; FAIL=0; WARN=0
ok()   { printf '  [ OK ]  %-34s %s\n' "$1" "${2:-}"; PASS=$((PASS+1)); }
bad()  { printf '  [FAIL]  %-34s %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
warn() { printf '  [WARN]  %-34s %s\n' "$1" "${2:-}"; WARN=$((WARN+1)); }
hdr()  { printf '\n%s\n' "$1"; }

printf '=== %s @ %s ===\n' "$(hostname)" "$(date -Is)"

hdr "Out-of-band access"
if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
    ok "sshd" "active"
else
    bad "sshd" "inactive — no way back in if X breaks"
fi
if command -v tailscale >/dev/null 2>&1; then
    TS="$(tailscale ip -4 2>/dev/null | head -1)"
    [[ -n "$TS" ]] && ok "tailscale ip" "$TS" || warn "tailscale" "installed, no IP"
else
    warn "tailscale" "not installed"
fi

hdr "Display detection"
shopt -s nullglob
CONNECTED=""
for s in /sys/class/drm/card*-*/status; do
    c="${s%/status}"; c="${c##*/}"
    case "$c" in *[Ww]riteback*|*[Vv]irtual*) continue ;; esac
    st="$(cat "$s" 2>/dev/null)"
    printf '          %-34s %s\n' "$c" "$st"
    [[ "$st" == connected ]] && CONNECTED="${CONNECTED:+$CONNECTED,}$c"
done
if [[ -n "$CONNECTED" ]]; then
    ok "physical monitor" "$CONNECTED"
    EXPECTED_MODE="physical"
else
    ok "physical monitor" "none (headless — dummy screen expected)"
    EXPECTED_MODE="dummy"
fi

hdr "Autoswitch"
if [[ -x /usr/local/sbin/display-autoswitch.sh ]]; then
    ok "switcher installed" "/usr/local/sbin/display-autoswitch.sh"
    /usr/local/sbin/display-autoswitch.sh --status 2>/dev/null | sed 's/^/          /'
    ACTUAL_MODE="$(/usr/local/sbin/display-autoswitch.sh --status 2>/dev/null | awk -F= '/current_mode/{print $2}')"
    [[ "$ACTUAL_MODE" == "$EXPECTED_MODE" ]] \
        && ok "mode matches hardware" "$ACTUAL_MODE" \
        || bad "mode matches hardware" "expected $EXPECTED_MODE, have ${ACTUAL_MODE:-unknown}"
else
    bad "switcher installed" "missing"
fi
systemctl is-enabled --quiet display-autoswitch.service 2>/dev/null \
    && ok "display-autoswitch.service" "enabled" \
    || bad "display-autoswitch.service" "not enabled"
[[ -f /etc/udev/rules.d/99-drm-hotplug.rules ]] \
    && ok "hotplug udev rule" "present" \
    || bad "hotplug udev rule" "missing"

hdr "X11 / display manager"
if grep -qiE '^[[:space:]]*WaylandEnable[[:space:]]*=[[:space:]]*false' /etc/gdm3/custom.conf 2>/dev/null; then
    ok "GDM pinned to X11" "WaylandEnable=false"
else
    bad "GDM pinned to X11" "Wayland still possible — AnyDesk will show a black screen"
fi
systemctl is-active --quiet display-manager.service 2>/dev/null \
    && ok "display-manager" "active" \
    || bad "display-manager" "inactive"
if pgrep -a Xorg >/dev/null 2>&1; then
    ok "Xorg running" "$(pgrep -a Xorg | head -1 | cut -c1-70)"
else
    bad "Xorg running" "no Xorg process — AnyDesk has nothing to capture"
fi

# Resolution as seen by the running X server (greeter or user session).
XAUTH="$(find /run/user -maxdepth 3 -name 'Xauthority' 2>/dev/null | head -1)"
[[ -z "$XAUTH" ]] && XAUTH="$(find /run/user -maxdepth 3 -name 'xauth_*' 2>/dev/null | head -1)"
if [[ -n "$XAUTH" ]] && command -v xrandr >/dev/null 2>&1; then
    RES="$(DISPLAY=:0 XAUTHORITY="$XAUTH" xrandr 2>/dev/null | awk '/\*/{print $1; exit}')"
    [[ -n "$RES" ]] && ok "active resolution" "$RES" || warn "active resolution" "xrandr returned nothing"
else
    warn "active resolution" "no Xauthority readable as $(id -un) — re-run with sudo"
fi

hdr "AnyDesk"
if dpkg -l anydesk 2>/dev/null | grep -q '^ii'; then
    ok "package" "$(dpkg -l anydesk | awk '/^ii/{print $3}')"
else
    bad "package" "not installed"
fi
systemctl is-active --quiet anydesk 2>/dev/null \
    && ok "service" "active" \
    || bad "service" "inactive"
if command -v anydesk >/dev/null 2>&1; then
    AID="$(anydesk --get-id 2>/dev/null || true)"
    [[ -n "$AID" ]] && ok "AnyDesk ID" "$AID" || bad "AnyDesk ID" "not assigned — check outbound 443/6568"
fi

hdr "Power / reachability"
for t in sleep.target suspend.target hibernate.target; do
    if systemctl is-enabled "$t" 2>/dev/null | grep -q masked; then
        ok "$t" "masked"
    else
        warn "$t" "not masked — unit can suspend itself out of reach"
    fi
done

printf '\n=== %d pass, %d warn, %d FAIL ===\n' "$PASS" "$WARN" "$FAIL"
(( FAIL == 0 )) || { echo "See docs/08-troubleshooting.md and start at Step 1."; exit 1; }
echo "Unit is good. Update UNIT-INVENTORY.md 'Last verified' to $(date +%F)."
