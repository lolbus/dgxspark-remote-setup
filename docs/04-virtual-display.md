# 04 — The virtual (dummy) display

## What gets installed

| Path | Purpose |
|---|---|
| `/etc/X11/autoswitch/xorg.conf.dummy` | The virtual-screen config. Copied to `/etc/X11/xorg.conf` when no monitor is attached |
| `/etc/X11/autoswitch/xorg.conf.physical` | The config restored when a monitor **is** attached. **Empty file = remove `/etc/X11/xorg.conf` = stock Xorg auto-detect**, which is the normal state on a DGX Spark |
| `/etc/X11/xorg.conf` | The live config. Owned by the switcher — do not hand-edit it; edit the variant and re-run the switcher with `--force` |
| `/var/backups/dgx-virtualscreen/` | One-time backups of anything the installer overwrote |

## The dummy config, explained

| Directive | Value | Reason |
|---|---|---|
| `Driver` | `dummy` | Software framebuffer from `xserver-xorg-video-dummy`. Exists with no hardware attached, which is the whole point |
| `VideoRam` | `262144` (256 MiB) | Must cover width x height x 4 bytes for the largest mode. 2560x1440x32bpp is ~14 MiB; 256 MiB leaves room for compositing |
| `Modeline` entries | 1920x1080, 1600x900, 2560x1440 | The dummy driver only offers modes you declare. Three covers the useful range; add more if a remote operator needs them |
| `Virtual` | `2560 1440` | The framebuffer ceiling. `xrandr` cannot switch to a mode larger than this, so it must be >= the largest modeline |
| `AutoAddGPU` | `false` | Stops Xorg attaching the NVIDIA device as a second GPU screen, which produces an extra empty screen that AnyDesk may capture instead of the real one |
| `BlankTime`/`StandbyTime`/`SuspendTime`/`OffTime` | `0` | DPMS off. A blanked virtual screen shows the remote operator a black window with no obvious cause |

## Changing the remote desktop resolution

The mode can be changed live over SSH without restarting X:

```bash
# find the running X server's auth file
XAUTH=$(sudo find /run/user -maxdepth 3 -name 'Xauthority' | head -1)
sudo DISPLAY=:0 XAUTHORITY="$XAUTH" xrandr                  # list modes
sudo DISPLAY=:0 XAUTHORITY="$XAUTH" xrandr -s 2560x1440     # switch
```

To make a new size permanent, add its modeline to `config/xorg.conf.dummy`, raise `Virtual`
if needed, re-install it, and re-run the switcher:

```bash
sudo install -m 0644 config/xorg.conf.dummy /etc/X11/autoswitch/xorg.conf.dummy
sudo /usr/local/sbin/display-autoswitch.sh --force   # DESTRUCTIVE: restarts the DM
```

Generate a modeline for an arbitrary size with `cvt 3840 2160 60`.

## What this does not affect

The dummy driver governs the **X desktop only**. `nvidia-smi`, CUDA, vLLM, containers and
every compute workload on the GB10 are untouched — they do not go through the X server. The
cost is that the remote desktop itself is software-rendered: fine for terminals, editors,
browsers and dashboards; poor for 3D, video playback and heavy compositing.

## Alternatives, and when to reach for them

| Alternative | Use when | Cost |
|---|---|---|
| HDMI/DP EDID emulator plug | Somebody can physically touch the unit | A port consumed; an undocumented hardware dependency |
| NVIDIA `ConnectedMonitor` + `CustomEDID` | You need an accelerated remote desktop | Per-unit EDID capture and connector name; breaks on driver changes. VERIFY-ON-UNIT on every box |
| `x11vnc` / `xrdp` with a virtual display | AnyDesk is not permitted on the network | Different access-control model; still needs a screen to capture |

See [`01-overview.md`](01-overview.md) for why the dummy driver was chosen over these.
