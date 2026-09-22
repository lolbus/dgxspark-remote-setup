#!/usr/bin/env bash
#
# healthcheck.sh — pass/fail gate for a built unit. Exit 0 = good.
# Prints the values UNIT-INVENTORY.md needs.
#
# NOT part of the validated procedure in Manual-Direct-commands.txt; that
# document's own verification is Step 7, transcribed in verify-display-mode.sh.

set -uo pipefail
DIR=/etc/X11/display-modes
XCONF=/etc/X11/xorg.conf
PASS=0; FAIL=0; WARN=0
ok()   { printf '  [ OK ]  %-30s %s\n' "$1" "${2:-}"; PASS=$((PASS+1)); }
bad()  { printf '  [FAIL]  %-30s %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
warn() { printf '  [WARN]  %-30s %s\n' "$1" "${2:-}"; WARN=$((WARN+1)); }
hdr()  { printf '\n%s\n' "$1"; }

printf '=== %s @ %s ===\n' "$(hostname)" "$(date -Is)"

hdr "Out-of-band access"
if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
    ok "sshd" "active"; else bad "sshd" "inactive"; fi
TS="$(command -v tailscale >/dev/null && tailscale ip -4 2>/dev/null | head -1)"
[[ -n "$TS" ]] && ok "tailscale ip" "$TS" || warn "tailscale" "no IP"

hdr "Monitor detection"
if command -v nvidia-xconfig >/dev/null 2>&1; then
    N="$(nvidia-xconfig --query-gpu-info 2>/dev/null | awk -F': *' '/Number of Display Devices/{print $2; exit}')"
    if [[ -n "${N:-}" ]]; then
        ok "display devices" "$N"
        [[ "$N" -gt 0 ]] 2>/dev/null && EXPECTED=physical || EXPECTED=headless
    else
        bad "display devices" "nvidia-xconfig returned nothing"; EXPECTED=unknown
    fi
else
    bad "nvidia-xconfig" "missing — switcher cannot detect monitors"; EXPECTED=unknown
fi

hdr "Mode"
for f in physical headless; do
    [[ -s "$DIR/$f.conf" ]] && ok "$f.conf" "present" || bad "$f.conf" "missing"
done
if cmp -s "$DIR/headless.conf" "$XCONF"; then LIVE=headless
elif cmp -s "$DIR/physical.conf" "$XCONF"; then LIVE=physical
else LIVE=unknown; fi
if [[ "$LIVE" == "unknown" ]]; then
    bad "live xorg.conf" "matches neither variant (hand-edited?)"
elif [[ "$EXPECTED" == "unknown" ]]; then
    warn "live xorg.conf" "$LIVE (cannot confirm — detection failed)"
elif [[ "$LIVE" == "$EXPECTED" ]]; then
    ok "live xorg.conf" "$LIVE (matches monitor state)"
else
    bad "live xorg.conf" "$LIVE, expected $EXPECTED"
fi

hdr "Switcher"
systemctl is-enabled --quiet display-mode.service 2>/dev/null \
    && ok "display-mode.service" "enabled" || bad "display-mode.service" "not enabled"
systemctl is-active --quiet display-mode.service 2>/dev/null \
    && ok "watcher running" "active" || bad "watcher running" "inactive — no live switching"
[[ -x /usr/local/sbin/display-mode.sh ]] \
    && ok "display-mode.sh" "$(grep -cE '^(POLL|PLUG_POLLS|UNPLUG_POLLS)=' /usr/local/sbin/display-mode.sh) timing params" \
    || bad "display-mode.sh" "missing"
LAST="$(journalctl -t display-mode -b --no-pager 2>/dev/null | tail -1)"
[[ -n "$LAST" ]] && ok "last switch" "${LAST:0:70}" || warn "last switch" "no entries this boot"

hdr "Display stack"
systemctl is-active --quiet gdm 2>/dev/null && ok "gdm" "active" || bad "gdm" "inactive"
if [[ "$LIVE" == "headless" ]]; then
    grep -qh 'LoadModule: "dummy"' /var/log/Xorg.0.log \
        /var/lib/gdm3/.local/share/xorg/Xorg.0.log 2>/dev/null \
        && ok "Xorg loaded dummy" "yes" \
        || bad "Xorg loaded dummy" "no dummy LoadModule line — screen may be unusable"
fi

hdr "AnyDesk"
dpkg -l anydesk 2>/dev/null | grep -q '^ii' \
    && ok "package" "$(dpkg -l anydesk | awk '/^ii/{print $3}')" || bad "package" "not installed"
systemctl is-active --quiet anydesk 2>/dev/null && ok "service" "active" || bad "service" "inactive"
AID="$(command -v anydesk >/dev/null && anydesk --get-id 2>/dev/null)"
[[ -n "$AID" ]] && ok "AnyDesk ID" "$AID" || bad "AnyDesk ID" "not assigned"

printf '\n=== %d pass, %d warn, %d FAIL ===\n' "$PASS" "$WARN" "$FAIL"
(( FAIL == 0 )) || { echo "See docs/08-troubleshooting.md, Step 1."; exit 1; }
echo "Unit is good. Update UNIT-INVENTORY.md 'Last verified' to $(date +%F)."
