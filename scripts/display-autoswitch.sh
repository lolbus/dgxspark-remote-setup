#!/usr/bin/env bash
#
# display-autoswitch.sh — install to /usr/local/sbin/display-autoswitch.sh
#
# Selects the Xorg config that matches the current physical-monitor state and
# restarts the display manager ONLY when the selection actually changes.
#
#   no monitor connected  -> /etc/X11/xorg.conf := xorg.conf.dummy
#   monitor connected     -> /etc/X11/xorg.conf := xorg.conf.physical
#                            (or removed, if xorg.conf.physical is empty =
#                             stock Xorg auto-detect)
#
# Invoked by:
#   - display-autoswitch.service at boot, with --boot (no DM restart; the DM
#     has not started yet)
#   - 99-drm-hotplug.rules on every DRM hotplug event, with no flags
#
# Exit codes: 0 no change or change applied, 1 usage/permission error,
#             2 required config variant missing.

set -euo pipefail

VARIANT_DIR="${VARIANT_DIR:-/etc/X11/autoswitch}"
XORG_CONF="${XORG_CONF:-/etc/X11/xorg.conf}"
DUMMY_CONF="${VARIANT_DIR}/xorg.conf.dummy"
PHYS_CONF="${VARIANT_DIR}/xorg.conf.physical"
STATE_FILE="${STATE_FILE:-/run/display-autoswitch.state}"
LOCK_FILE="${LOCK_FILE:-/run/lock/display-autoswitch.lock}"
LOG_FILE="${LOG_FILE:-/var/log/display-autoswitch.log}"
DEBOUNCE_SECONDS="${DEBOUNCE_SECONDS:-4}"

BOOT_MODE=0
FORCE=0
DRY_RUN=0
STATUS_ONLY=0

usage() {
    cat <<'USAGE'
Usage: display-autoswitch.sh [--boot] [--force] [--dry-run] [--status] [--help]

  --boot     Boot-time invocation: apply the config but never restart the
             display manager (it has not started yet).
  --force    Re-apply even if the desired mode equals the recorded mode.
  --dry-run  Print what would change; touch nothing.
  --status   Print current detection and mode, then exit.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --boot)    BOOT_MODE=1 ;;
        --force)   FORCE=1 ;;
        --dry-run) DRY_RUN=1 ;;
        --status)  STATUS_ONLY=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

log() {
    local line
    line="$(date -Is) [$$] $*"
    printf '%s\n' "$line" >> "$LOG_FILE" 2>/dev/null || true
    printf '%s\n' "$line"
}

# Returns 0 and prints the connector name if any real display is connected.
# Writeback and virtual connectors are excluded: several DRM drivers report
# writeback connectors as permanently "connected", which would pin the unit
# into physical mode forever.
physical_connector() {
    local status_file connector state
    shopt -s nullglob
    for status_file in /sys/class/drm/card*-*/status; do
        [[ -r "$status_file" ]] || continue
        connector="${status_file%/status}"
        connector="${connector##*/}"
        case "$connector" in
            *[Ww]riteback*|*[Vv]irtual*|*None*) continue ;;
        esac
        state="$(cat "$status_file" 2>/dev/null || echo unknown)"
        if [[ "$state" == "connected" ]]; then
            printf '%s' "$connector"
            return 0
        fi
    done
    return 1
}

recorded_mode() {
    [[ -r "$STATE_FILE" ]] && cat "$STATE_FILE" || echo "unknown"
}

# Infer the mode from the file on disk, for the first run when no state file
# exists yet, or after a reboot (/run is tmpfs).
mode_on_disk() {
    if [[ ! -e "$XORG_CONF" ]]; then
        # No xorg.conf at all == stock auto-detect == physical.
        echo "physical"; return
    fi
    if [[ -r "$DUMMY_CONF" ]] && cmp -s "$XORG_CONF" "$DUMMY_CONF"; then
        echo "dummy"; return
    fi
    echo "physical"
}

dm_unit() {
    # Ubuntu 24.04 ships gdm3; display-manager.service is the generic alias.
    if systemctl list-unit-files display-manager.service >/dev/null 2>&1; then
        echo "display-manager.service"
    else
        echo ""
    fi
}

apply_mode() {
    local mode="$1" src
    case "$mode" in
        dummy)
            src="$DUMMY_CONF"
            [[ -s "$src" ]] || { log "FATAL: $src missing or empty"; exit 2; }
            if (( DRY_RUN )); then
                log "DRY-RUN: would install $src -> $XORG_CONF"
            else
                install -o root -g root -m 0644 "$src" "$XORG_CONF"
                log "installed dummy config -> $XORG_CONF"
            fi
            ;;
        physical)
            if [[ -s "$PHYS_CONF" ]]; then
                if (( DRY_RUN )); then
                    log "DRY-RUN: would install $PHYS_CONF -> $XORG_CONF"
                else
                    install -o root -g root -m 0644 "$PHYS_CONF" "$XORG_CONF"
                    log "installed physical config -> $XORG_CONF"
                fi
            else
                if (( DRY_RUN )); then
                    log "DRY-RUN: would remove $XORG_CONF (stock auto-detect)"
                else
                    rm -f "$XORG_CONF"
                    log "removed $XORG_CONF (stock Xorg auto-detect)"
                fi
            fi
            ;;
        *) log "FATAL: unknown mode '$mode'"; exit 1 ;;
    esac
}

restart_dm() {
    local unit
    unit="$(dm_unit)"
    if [[ -z "$unit" ]]; then
        log "no display-manager unit found; skipping restart"
        return 0
    fi
    if (( BOOT_MODE )); then
        log "boot mode: not restarting $unit"
        return 0
    fi
    if ! systemctl is-active --quiet "$unit"; then
        log "$unit not active; skipping restart"
        return 0
    fi
    if (( DRY_RUN )); then
        log "DRY-RUN: would restart $unit"
        return 0
    fi
    log "DESTRUCTIVE: restarting $unit — any live AnyDesk session drops here"
    systemctl restart "$unit" || log "WARNING: restart of $unit failed"
}

main() {
    local connector desired current

    if connector="$(physical_connector)"; then
        desired="physical"
    else
        connector="none"
        desired="dummy"
    fi

    current="$(recorded_mode)"
    [[ "$current" == "unknown" ]] && current="$(mode_on_disk)"

    if (( STATUS_ONLY )); then
        printf 'connected_connector=%s\ndesired_mode=%s\ncurrent_mode=%s\nxorg_conf=%s\n' \
            "$connector" "$desired" "$current" \
            "$([[ -e "$XORG_CONF" ]] && echo "$XORG_CONF" || echo '(absent, auto-detect)')"
        exit 0
    fi

    if [[ $EUID -ne 0 ]]; then
        echo "must run as root (or use --status)" >&2
        exit 1
    fi

    mkdir -p "$(dirname "$LOCK_FILE")" "$(dirname "$STATE_FILE")" 2>/dev/null || true
    exec 9>"$LOCK_FILE"
    if ! flock -w 45 9; then
        log "another instance holds the lock; exiting"
        exit 0
    fi

    # Hotplug fires several events per physical plug/unplug. Settle first, then
    # re-read, so one plug produces one switch.
    if (( ! BOOT_MODE )) && (( DEBOUNCE_SECONDS > 0 )); then
        sleep "$DEBOUNCE_SECONDS"
        if connector="$(physical_connector)"; then desired="physical"
        else connector="none"; desired="dummy"; fi
    fi

    if [[ "$desired" == "$current" ]] && (( ! FORCE )); then
        log "no change: connector=$connector mode=$current"
        printf '%s' "$current" > "$STATE_FILE" 2>/dev/null || true
        exit 0
    fi

    log "switching: connector=$connector $current -> $desired (force=$FORCE boot=$BOOT_MODE)"
    apply_mode "$desired"
    (( DRY_RUN )) || printf '%s' "$desired" > "$STATE_FILE"
    restart_dm
    log "done: mode=$desired"
}

main "$@"
