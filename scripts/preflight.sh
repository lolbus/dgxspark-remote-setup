#!/usr/bin/env bash
#
# preflight.sh — read-only survey before installing. Changes nothing.
#
# NOT part of the validated procedure in Manual-Direct-commands.txt. It is a
# convenience that checks the preconditions that procedure assumes.

set -uo pipefail
hdr() { printf '\n=== %s ===\n' "$1"; }
kv()  { printf '  %-30s %s\n' "$1" "$2"; }

hdr "Identity"
kv "hostname" "$(hostname)"
kv "os"       "$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")"
kv "kernel"   "$(uname -r)"
kv "arch"     "$(uname -m)"

hdr "GPU and monitor count (how the switcher decides)"
kv "nvidia-smi" "$(command -v nvidia-smi >/dev/null && nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null | head -1 || echo 'not present')"
if command -v nvidia-xconfig >/dev/null 2>&1; then
    nvidia-xconfig --query-gpu-info 2>/dev/null \
        | grep -E "Number of Display Devices|EDID Name" | sed 's/^/  /' \
        || kv "query-gpu-info" "returned nothing"
else
    kv "nvidia-xconfig" "NOT PRESENT — the switcher cannot detect monitors without it"
fi

hdr "Xorg config (Step 2 requires this)"
if [[ -s /etc/X11/xorg.conf ]]; then
    kv "/etc/X11/xorg.conf" "present"
    grep -n 'Driver' /etc/X11/xorg.conf | sed 's/^/  /'
else
    kv "/etc/X11/xorg.conf" "ABSENT — Step 2 will stop; nothing to save as physical.conf"
fi
kv "dummy driver pkg" "$(dpkg -l xserver-xorg-video-dummy 2>/dev/null | awk '/^ii/{print $3}' || echo 'not installed')"
kv "display-mode.service" "$(systemctl is-enabled display-mode.service 2>/dev/null || echo 'not installed')"

hdr "Display manager"
kv "gdm" "$(systemctl is-active gdm 2>/dev/null || echo inactive)"
kv "gdm WaylandEnable" "$(grep -E '^[[:space:]]*#?[[:space:]]*WaylandEnable' /etc/gdm3/custom.conf 2>/dev/null | tr -d ' ' | paste -sd, - || echo 'not set')"

hdr "AnyDesk"
kv "package" "$(dpkg -l anydesk 2>/dev/null | awk '/^ii/{print $3}' || echo 'not installed')"
kv "service" "$(systemctl is-active anydesk 2>/dev/null || echo 'n/a')"
kv "id"      "$(command -v anydesk >/dev/null && anydesk --get-id 2>/dev/null || echo 'n/a')"

hdr "Out-of-band access (your way back in)"
kv "sshd"      "$(systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null || echo 'INACTIVE')"
kv "tailscale" "$(command -v tailscale >/dev/null && tailscale ip -4 2>/dev/null | head -1 || echo 'not present')"

hdr "Blocking conditions"
rc=0
if ! systemctl is-active --quiet ssh 2>/dev/null && ! systemctl is-active --quiet sshd 2>/dev/null; then
    echo "  BLOCKER: no active SSH server. Every switch restarts GDM; without SSH a"
    echo "           failed config on a remote-only unit means a site visit."
    rc=1
fi
if ! command -v nvidia-xconfig >/dev/null 2>&1; then
    echo "  BLOCKER: nvidia-xconfig missing — monitor_present() in display-mode.sh"
    echo "           would always report 0 and pin the unit to headless."
    rc=1
fi
if [[ ! -s /etc/X11/xorg.conf ]]; then
    echo "  BLOCKER: no /etc/X11/xorg.conf to save as physical.conf (Step 2)."
    rc=1
fi
(( rc == 0 )) && echo "  none — safe to proceed"
exit $rc
