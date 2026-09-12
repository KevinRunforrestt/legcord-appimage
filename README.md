# Legcord AppImage

Portable AppImage of [Legcord](https://github.com/Legcord/Legcord) built using the
[Anylinux-AppImages](https://github.com/pkgforge-dev/Anylinux-AppImages) methodology.

## What is this?

A single-file AppImage of Legcord (custom Discord client based on Electron) that runs
on **any Linux distribution**, including:

- glibc distros (Ubuntu 14.04+, Debian, Arch, Fedora, openSUSE)
- musl libc distros (Alpine, Void musl)
- NixOS (no wrapper needed)

The AppImage bundles **everything**: libc, the dynamic linker (`ld-linux-x86-64.so.2`),
mesa/Vulkan/OpenGL stacks, audio (PulseAudio/PipeWire), X11 and Wayland libraries,
plus the Vencord and koffi native modules shipped inside Legcord's `app.asar.unpacked`.

## Why a wrapper script?

Legcord ships as an Electron binary. Electron on Linux needs several Chromium
command-line flags to behave correctly inside an AppImage:

| Flag | Why |
| --- | --- |
| `--ozone-platform-hint=auto` | Auto-selects Wayland or X11 at startup |
| `--use-gl=angle --use-angle=opengl` | Forces OpenGL native rendering (works with bundled mesa) |
| `--ignore-gpu-blocklist` | Prevents Chromium from disabling the GPU |
| `--disable-gpu-sandbox` | Avoids conflicts with uruntime namespaces |
| `--disable-features=CalculateNativeWinOcclusion` | Prevents the window from being marked as hidden |
| `--process-per-site` | Reduces RAM by sharing renderer processes per site |
| `--enable-low-res-tiling` | Reduces GPU compositor memory |

These flags are injected by the wrapper script that lives at `AppDir/bin/legcord`,
which calls the real Electron binary at `AppDir/bin/legcord.real`.

## Local build

```bash
docker run --rm -it -v "$PWD:/work" -w /work ghcr.io/pkgforge-dev/archlinux:latest ./build.sh
```

Or run directly on Arch Linux (requires `pacman`, `sudo`, and `quick-sharun` installed
via `anylinux-setup-action`).

## CI

The workflow at `.github/workflows/appimage.yml` is **manual only**
(`workflow_dispatch`). It is not triggered by pushes or schedules — you
decide when to rebuild by clicking "Run workflow" in the Actions tab on GitHub.

To enable periodic rebuilds, add this under `on:` in the workflow:

```yaml
on:
  workflow_dispatch: {}
  schedule:
    - cron: "0 7 1/7 * *"
```

## Verification

After building, the script extracts the AppImage and verifies:

- `ld-linux-x86-64.so.2` is bundled
- `libc.so*` is bundled
- The wrapper script is in place at `bin/legcord`
- The real Electron binary is at `bin/legcord.real`

## Tuning flags

If a flag causes instability (e.g. blank window, GPU process crash), edit the
`LEGCORD_FLAGS` variable at the top of `build.sh`, comment out the problematic
flag, and rebuild. Do **not** remove the wrapper itself — that would break the
`.desktop` file action shortcuts (`mute`, `deafen`, `leave`, `opensettings`).
