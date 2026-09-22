# 04 — The two display configs

> **Provenance.** Transcribed from Steps 2 and 3 of
> [`../Manual-Direct-commands.txt`](../Manual-Direct-commands.txt).

Both live in `/etc/X11/display-modes/`. The switcher copies one of them over
`/etc/X11/xorg.conf`. `/etc/X11/xorg.conf` is owned by the switcher — do not hand-edit it;
edit the variant.

| Path | What it is |
|---|---|
| `/etc/X11/display-modes/physical.conf` | This unit's own DGX OS `xorg.conf`, copied at install time. Declares `Driver "nvidia"`. Used whenever a monitor is attached |
| `/etc/X11/display-modes/headless.conf` | The dummy screen. Used when no monitor is attached |
| `/etc/X11/xorg.conf` | The live config — a copy of one of the two above |

## physical.conf

Not authored — captured. Step 2 is:

```bash
sudo mkdir -p /etc/X11/display-modes \
  && sudo cp -p /etc/X11/xorg.conf /etc/X11/display-modes/physical.conf \
  && grep -n Driver /etc/X11/display-modes/physical.conf
```

The `grep` is a gate, not decoration. Output showing `Driver "nvidia"` means continue;
anything else means stop. Copying a config that does not drive the monitor gives a unit that
switches into a broken physical mode the moment somebody plugs a screen in — and on a
remote-only box you will not find out until someone is standing in front of it.

## headless.conf

```
Section "Device"
    Identifier "Dummy"
    Driver "dummy"
    VideoRam 256000
EndSection

Section "Screen"
    Identifier "DummyScreen"
    Device "Dummy"
    Monitor "DummyMonitor"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "1920x1080"
    EndSubSection
EndSection

Section "Monitor"
    Identifier "DummyMonitor"
    HorizSync 28.0-80.0
    VertRefresh 48.0-75.0
EndSection
```

One mode, 1920x1080, 256 MB of video RAM. This is the config validated on the Dell — it is
deliberately minimal. Adding modelines, a `Virtual` ceiling, `AutoAddGPU false` or DPMS
overrides may look like an improvement and has not been tested on GB10; if you want a
different remote resolution, change `Modes` and test it on one unit before the fleet.

## Changing the headless resolution

```bash
sudo sed -i 's/Modes "1920x1080"/Modes "2560x1440"/' /etc/X11/display-modes/headless.conf
sudo cp /etc/X11/display-modes/headless.conf /etc/X11/xorg.conf
sudo systemctl restart gdm     # DESTRUCTIVE: logs out the desktop
```

The dummy driver only offers modes it is given, and `VideoRam 256000` (250 MB) covers well
beyond 2560x1440 at 32bpp, so the memory line does not need changing for ordinary sizes.

## What this does not affect

These configs govern the X desktop only. `nvidia-smi`, CUDA, vLLM, containers and every
compute workload are untouched — they do not go through the X server. In headless mode the
desktop itself is software-rendered: fine for terminals, editors, browsers and dashboards;
poor for 3D and video playback.
