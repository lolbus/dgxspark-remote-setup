#!/bin/bash
# boot : choose xorg.conf before GDM starts
# watch: poll for monitor plug/unplug, switch config, restart GDM
DIR=/etc/X11/display-modes
XCONF=/etc/X11/xorg.conf
POLL=5           # seconds between checks
PLUG_POLLS=2     # monitor seen 2 polls in a row (~10 s) -> physical
UNPLUG_POLLS=24  # monitor gone 24 polls in a row (~120 s) -> headless

monitor_present() {
    local n
    n=$(nvidia-xconfig --query-gpu-info 2>/dev/null | awk -F': *' '/Number of Display Devices/{print $2; exit}')
    [ "${n:-0}" -gt 0 ] 2>/dev/null
}
current_mode() { cmp -s "$DIR/headless.conf" "$XCONF" && echo headless || echo physical; }
set_mode() { cp "$DIR/$1.conf" "$XCONF"; logger -t display-mode "switched to $1"; }

case "$1" in
boot)
    systemctl is-active --quiet gdm && exit 0   # only at real boot, not on watcher restart
    for i in $(seq 1 30); do nvidia-smi -L >/dev/null 2>&1 && break; sleep 1; done
    if monitor_present; then set_mode physical; else set_mode headless; fi
    ;;
watch)
    seen=0; gone=0
    while sleep "$POLL"; do
        if monitor_present; then seen=$((seen+1)); gone=0; else gone=$((gone+1)); seen=0; fi
        mode=$(current_mode)
        if [ "$mode" = headless ] && [ "$seen" -ge "$PLUG_POLLS" ]; then
            set_mode physical; systemctl restart gdm; seen=0
        elif [ "$mode" = physical ] && [ "$gone" -ge "$UNPLUG_POLLS" ]; then
            set_mode headless; systemctl restart gdm; gone=0
        fi
    done
    ;;
esac
