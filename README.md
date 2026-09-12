<div align="center">

# Legcord-AppImage 🐧

[![GitHub Downloads](https://img.shields.io/github/downloads/KevinRunforrestt/legcord-appimage/total?logo=github&label=GitHub%20Downloads)](https://github.com/KevinRunforrestt/legcord-appimage/releases/latest)
[![CI Build Status](https://github.com/KevinRunforrestt/legcord-appimage/actions/workflows/appimage.yml/badge.svg)](https://github.com/KevinRunforrestt/legcord-appimage/actions/workflows/appimage.yml)
[![Latest Release](https://img.shields.io/github/v/release/KevinRunforrestt/legcord-appimage)](https://github.com/KevinRunforrestt/legcord-appimage/releases/latest)

<p align="center">
  <img
    src="https://raw.githubusercontent.com/Legcord/Legcord/main/build/icon.png"
    alt="Legcord icon"
    width="128"
  />
</p>

| Latest Release | Upstream Repository |
| :---: | :---: |
| [Download](https://github.com/KevinRunforrestt/legcord-appimage/releases/latest) | [Legcord](https://github.com/Legcord/Legcord) |

</div>

---

An unofficial AppImage build of **Legcord** for Linux.

This AppImage is built using [sharun](https://github.com/VHSgunzo/sharun) and its wrapper, [quick-sharun](https://github.com/pkgforge-dev/Anylinux-AppImages/blob/main/useful-tools/quick-sharun.sh). These tools make it easy to turn binaries into reliable, portable packages without using containers or similar workarounds.

The AppImage bundles its dependencies and should work on most Linux distributions, including older and musl-based distributions.

It does not require FUSE to run, thanks to [uruntime](https://github.com/VHSgunzo/uruntime).

The CI runs automatically every 7 days and detects when a new Legcord version is released by comparing the upstream GitHub release tag with the `LATEST_VERSION` file in this repo. When a new version is detected, it builds the AppImage and publishes a new GitHub Release. Manual triggers from the Actions tab are also supported and always build, even if the version hasn't changed.

For more information, visit [Anylinux-AppImages](https://pkgforge-dev.github.io/Anylinux-AppImages/).

## Credits

Thanks to [Samueru-sama](https://github.com/Samueru-sama) and [fiftydinar](https://github.com/fiftydinar) for making AppImage builds quicker and easier with the [Anylinux-AppImages](https://github.com/pkgforge-dev/Anylinux-AppImages) tools.
