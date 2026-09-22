#!/usr/bin/env bash
#
# preflight.sh — read-only survey of a unit before anything is installed.
# Changes nothing. Run it first, paste the output into the build record.

set -uo pipefail

hdr() { printf '\n=== %s ===\n' "$1"; }
kv()  { printf '  %-28s %s\n' "$1" "$2"; }

hdr "Identity"
kv "hostname"        "$(hostname)"
kv "os"              "$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")"
kv "kernel"          "$(uname -r)"
kv "arch"            "$(uname -m)"
kv "uptime"          "$(uptime -p 2>/dev/null)"

hdr "GPU / driver"
kv "nvidia-smi"      "$(command -v nvidia-smi >/dev/null && nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null | head -1 || echo 'not present')"
kv "nvidia-drm modeset" "$(cat /sys/module/nvidia_drm/parameters/modeset 2>/dev/null || echo 'n/a')"

hdr "DRM connectors (this is what decides dummy vs physical)"
shopt -s nullglob
found=0
for s in /sys/class/drm/card*-*/status; do
    c="${s%/status}"; c="${c##*/}"
    kv "$c" "$(cat "$s" 2>/dev/null)"
    found=1
done
(( found )) || kv "(none)" "no DRM connectors exposed"

hdr "Display stack"
kv "display-manager"      "$(systemctl is-active display-manager.service 2>/dev/null) / $(basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" 2>/dev/null)"
kv "gdm WaylandEnable"    "$(grep -E '^[[:space:]]*#?[[:space:]]*WaylandEnable' /etc/gdm3/custom.conf 2>/dev/null | tr -d ' ' | paste -sd, - || echo 'not set (Wayland ON by default)')"
kv "gdm AutomaticLogin"   "$(grep -E '^[[:space:]]*#?[[:space:]]*AutomaticLogin' /etc/gdm3/custom.conf 2>/dev/null | tr -d ' ' | paste -sd, - || echo 'not set')"
kv "current session type" "${XDG_SESSION_TYPE:-$(loginctl show-session "$(loginctl 2>/dev/null | awk 'NR==2{print $1}')" -p Type --value 2>/dev/null || echo unknown)}"
kv "/etc/X11/xorg.conf"   "$([[ -e /etc/X11/xorg.conf ]] && echo present || echo 'absent (stock auto-detect)')"
kv "dummy driver pkg"     "$(dpkg -l xserver-xorg-video-dummy 2>/dev/null | awk '/^ii/{print $3}' || echo 'not installed')"
kv "autoswitch service"   "$(systemctl is-enabled display-autoswitch.service 2>/dev/null || echo 'not installed')"

hdr "AnyDesk"
kv "package"   "$(dpkg -l anydesk 2>/dev/null | awk '/^ii/{print $3}' || echo 'not installed')"
kv "service"   "$(systemctl is-active anydesk 2>/dev/null || echo 'n/a')"
kv "id"        "$(command -v anydesk >/dev/null && anydesk --get-id 2>/dev/null || echo 'n/a')"

hdr "Out-of-band access (your way back in if X breaks)"
kv "sshd"        "$(systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null || echo 'INACTIVE')"
kv "tailscale"   "$(command -v tailscale >/dev/null && tailscale ip -4 2>/dev/null | head -1 || echo 'not present')"
kv "ufw"         "$(command -v ufw >/dev/null && ufw status 2>/dev/null | head -1 || echo 'not present')"

hdr "Blocking conditions"
rc=0
if ! systemctl is-active --quiet ssh 2>/dev/null && ! systemctl is-active --quiet sshd 2>/dev/null; then
    echo "  BLOCKER: no active SSH server. Do not proceed — a failed Xorg config"
    echo "           with no SSH and no monitor means a site visit."
    rc=1
fi
if [[ "$(uname -m)" != "aarch64" ]]; then
    echo "  WARNING: arch is not aarch64. This runbook targets GB10 / ARM64."
fi
(( rc == 0 )) && echo "  none — safe to proceed"
exit $rc
