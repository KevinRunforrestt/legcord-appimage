#!/bin/sh
# =============================================================================
# build.sh - Legcord AppImage (Anylinux methodology)
# =============================================================================
# Downloads the latest Legcord tarball from GitHub and packages it with
# quick-sharun (pkgforge-dev/Anylinux-AppImages).
#
# Layout produced in AppDir/bin/:
#   legcord         -> wrapper script that injects Chromium flags
#   legcord.real    -> the real Electron binary (210 MB)
#   *.so*, *.pak, *.dat, locales/, resources/  -> Chromium / Vencord assets
#
# Injected Chromium flags (verified valid for Electron >= 28):
#   Wayland/X11 dual:        --ozone-platform-hint=auto
#   Hardware acceleration:   --use-gl=angle --use-angle=opengl --ignore-gpu-blocklist
#   Sandbox/namespace fix:  --disable-gpu-sandbox
#   Window visibility fix:   --disable-features=CalculateNativeWinOcclusion
#   RAM optimization:        --process-per-site --enable-low-res-tiling
#
# If any flag causes instability, comment it out in the LEGCORD_FLAGS variable
# below and rebuild. Do NOT remove the wrapper entirely or the original
# .desktop file actions (mute/deafen/leave/opensettings) will break.
# =============================================================================

set -eu

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
ARCH=$(uname -m)

# Repository to query for the latest release (without API token, anonymous)
LEGCORD_REPO="Legcord/Legcord"
LEGCORD_API="https://api.github.com/repos/${LEGCORD_REPO}/releases/latest"

# Select the right asset name per architecture
case "$ARCH" in
    x86_64)
        ASSET_PATTERN="linux-x64.tar.gz"
        LEGCORD_ARCH_DIR="linux-x64"
        ;;
    aarch64)
        ASSET_PATTERN="linux-arm64.tar.gz"
        LEGCORD_ARCH_DIR="linux-arm64"
        ;;
    armv7l|armhf)
        ASSET_PATTERN="linux-armv7l.tar.gz"
        LEGCORD_ARCH_DIR="linux-armv7l"
        ;;
    *)
        echo "ERROR: Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Chromium flags injected by the wrapper script (see LEGCORD_FLAGS below).
# Remove individual flags here if they cause instability.
LEGCORD_FLAGS='
    --ozone-platform-hint=auto
    --use-gl=angle
    --use-angle=opengl
    --ignore-gpu-blocklist
    --disable-gpu-sandbox
    --disable-features=CalculateNativeWinOcclusion
    --process-per-site
    --enable-low-res-tiling
'

# ---------------------------------------------------------------------------
# STEP 1: Install dependencies (Arch Linux container)
# ---------------------------------------------------------------------------
echo "=== STEP 1: Install dependencies ==="
pacman -Syu --noconfirm \
    base-devel \
    wget \
    strace \
    jq \
    brotli \
    libappindicator-gtk3 \
    libatomic

if [ "$ARCH" = 'x86_64' ]; then
    pacman -Syu --noconfirm libva-intel-driver
fi

# Debloated packages: recortan libLLVM, mesa, vulkan, Qt, GTK, libicudata
# hasta ~50 MiB en AppImages que usan GPU (frente a >200 MiB sin recortar)
get-debloated-pkgs --add-mesa --prefer-nano
get-debloated-pkgs --add-common --prefer-nano intel-media-driver-mini

# ---------------------------------------------------------------------------
# STEP 2: Download Legcord tarball from GitHub releases
# ---------------------------------------------------------------------------
echo ""
echo "=== STEP 2: Download Legcord ($ARCH) ==="

echo "Querying: $LEGCORD_API"
RELEASE_JSON=$(wget -q --header="User-Agent: legcord-appimage" "$LEGCORD_API" -O -)
TARBALL_URL=$(echo "$RELEASE_JSON" \
    | jq -r --arg pat "$ASSET_PATTERN" \
        '.assets[] | select(.name | endswith($pat)) | .browser_download_url' \
    | head -1)

if [ -z "$TARBALL_URL" ] || [ "$TARBALL_URL" = "null" ]; then
    echo "ERROR: Could not find asset matching '*$ASSET_PATTERN' in $LEGCORD_REPO"
    echo "$RELEASE_JSON" | jq '.assets[].name'
    exit 1
fi

VERSION=$(echo "$RELEASE_JSON" | jq -r '.tag_name | ltrimstr("v")')
echo "Latest Legcord version: $VERSION"
echo "Tarball URL: $TARBALL_URL"

mkdir -p ./AppDir/bin
echo "Downloading tarball..."
wget -q "$TARBALL_URL" -O - \
    | tar xzf - --strip-components=1 -C ./AppDir/bin

# Sanity-check: the binary must be there
if [ ! -x "./AppDir/bin/legcord" ]; then
    echo "ERROR: ./AppDir/bin/legcord not found after extraction"
    find ./AppDir/bin -maxdepth 1 -type f | head -20
    exit 1
fi

# quick-sharun needs +x on binaries and .so files for ldd to work
chmod +x ./AppDir/bin/legcord ./AppDir/bin/chrome-sandbox ./AppDir/bin/chrome_crashpad_handler 2>/dev/null || true
chmod +x ./AppDir/bin/*.so* 2>/dev/null || true

echo "Files in AppDir/bin/: $(ls ./AppDir/bin/ | wc -l)"

# ---------------------------------------------------------------------------
# STEP 3: Create wrapper script that injects Chromium flags
# ---------------------------------------------------------------------------
echo ""
echo "=== STEP 3: Create wrapper script with Chromium flags ==="

# Rename the real binary
mv ./AppDir/bin/legcord ./AppDir/bin/legcord.real

# Create wrapper (single-line so the shebang and exec are preserved)
WRAPPER_FLAGS=$(echo "$LEGCORD_FLAGS" | tr -s '[:space:]' ' ' | sed 's/^ //;s/ $//')

cat > ./AppDir/bin/legcord <<EOF
#!/bin/sh
# Wrapper: invokes the real Electron binary with optimal Chromium flags.
# Generated by build.sh -- do NOT edit manually, edit build.sh instead.
HERE="\$(dirname "\$(readlink -f "\$0")")"
exec "\$HERE/legcord.real" \\
    $WRAPPER_FLAGS \\
    "\$@"
EOF
chmod +x ./AppDir/bin/legcord

echo "Wrapper created with flags:"
echo "$WRAPPER_FLAGS" | tr ' ' '\n' | grep -v '^$' | sed 's/^/  /'

# ---------------------------------------------------------------------------
# STEP 4: Create desktop file and icon
# ---------------------------------------------------------------------------
echo ""
echo "=== STEP 4: Create desktop file and icon ==="

# Use the highest-resolution icon we can find; prefer 512x512, fall back to 256
ICON_SRC=""
for size in 512x512 256x256 128x128 48x48 64x64; do
    candidate="/usr/share/icons/hicolor/${size}/apps/legcord.png"
    if [ -f "$candidate" ]; then
        ICON_SRC="$candidate"
        break
    fi
done

# If the .deb hasn't installed icons (e.g., we used the tarball directly),
# pull a fallback icon from the GitHub release
if [ -z "$ICON_SRC" ]; then
    FALLBACK_ICON_URL=$(echo "$RELEASE_JSON" \
        | jq -r '.assets[] | select(.name | endswith(".png") or endswith(".svg")) | .browser_download_url' \
        | head -1)
    if [ -n "$FALLBACK_ICON_URL" ] && [ "$FALLBACK_ICON_URL" != "null" ]; then
        mkdir -p /usr/share/icons/hicolor/512x512/apps
        wget -q "$FALLBACK_ICON_URL" -O /usr/share/icons/hicolor/512x512/apps/legcord.png
        ICON_SRC="/usr/share/icons/hicolor/512x512/apps/legcord.png"
    fi
fi

if [ -z "$ICON_SRC" ]; then
    echo "ERROR: No icon available. Install the Legcord .deb first, or include an icon in the repo."
    exit 1
fi

# Download the .deb's icon set if we don't have icons (needed for proper icon
# discovery by sharun and for the .desktop file)
if [ ! -f /usr/share/applications/legcord.desktop ]; then
    echo "Fetching Legcord .deb to extract desktop file and icons..."
    DEB_URL=$(echo "$RELEASE_JSON" \
        | jq -r --arg arch "$ARCH" \
            '.assets[] | select(.name | endswith(".deb")) | select(.name | contains(if $arch=="x86_64" then "amd64" elif $arch=="aarch64" then "arm64" else "armv7l" end)) | .browser_download_url' \
        | head -1)
    if [ -n "$DEB_URL" ] && [ "$DEB_URL" != "null" ]; then
        TMP_DEB=/tmp/legcord.deb
        wget -q "$DEB_URL" -O "$TMP_DEB"
        cd /tmp && ar x "$TMP_DEB" data.tar.xz 2>/dev/null || true
        if [ -f /tmp/data.tar.xz ]; then
            sudo tar -xJf /tmp/data.tar.xz -C / 2>/dev/null \
                ./usr/share/applications/legcord.desktop \
                ./usr/share/icons/hicolor 2>/dev/null || \
            tar -xJf /tmp/data.tar.xz -C / -- ./usr/share/applications ./usr/share/icons 2>/dev/null || true
            rm -f /tmp/data.tar.xz
        fi
        rm -f "$TMP_DEB"
        cd - >/dev/null
    fi
fi

# Use the system-installed desktop file if available, else write one
if [ -f /usr/share/applications/legcord.desktop ]; then
    DESKTOP_SRC=/usr/share/applications/legcord.desktop
    # Patch Exec= and Icon= to point inside the AppDir
    sed \
        -e 's|^Exec=.*|Exec=legcord %U|' \
        -e 's|^Icon=.*|Icon=legcord|' \
        -e 's|^Exec=AppRun |Exec=legcord |g' \
        "$DESKTOP_SRC" > ./AppDir/legcord.desktop
else
    cat > ./AppDir/legcord.desktop <<EOF
[Desktop Entry]
Name=Legcord
Exec=legcord %U
Terminal=false
Type=Application
Icon=legcord
StartupWMClass=legcord
Actions=mute;deafen;leave;opensettings
Comment=Legcord is a custom client designed to enhance your Discord experience while keeping everything lightweight.
MimeType=x-scheme-handler/discord;
Categories=Network;
X-AppImage-Name=Legcord
X-AppImage-Version=${VERSION}
X-AppImage-Arch=${ARCH}

[Desktop Action mute]
Name=Toggle Mute
Exec=legcord --mute %U

[Desktop Action deafen]
Name=Toggle Deafen
Exec=legcord --deafen %U

[Desktop Action leave]
Name=Leave Call
Exec=legcord --leave %U

[Desktop Action opensettings]
Name=Open Settings
Exec=legcord --opensettings %U
EOF
fi

# Copy icon to AppDir root (quick-sharun looks for it there) and .DirIcon
cp "$ICON_SRC" ./AppDir/legcord.png 2>/dev/null || true
cp "$ICON_SRC" ./AppDir/.DirIcon 2>/dev/null || true

echo "Desktop file: $(ls -la ./AppDir/legcord.desktop | awk '{print $5, $9}')"
echo "Icon: $ICON_SRC"

# ---------------------------------------------------------------------------
# STEP 5: Package with quick-sharun
# ---------------------------------------------------------------------------
echo ""
echo "=== STEP 5: Package with quick-sharun ==="

export ARCH VERSION
export OUTPATH=./dist
export OUTNAME="Legcord-${VERSION}-${ARCH}.AppImage"
export ADD_HOOKS="self-updater.hook:fix-namespaces.hook"
export UPINFO="gh-releases-zsync|${GITHUB_REPOSITORY:-Legcord}|${GITHUB_REPOSITORY_NAME:-Legcord-AppImage}|latest|*${ARCH}.AppImage.zsync"
export DESKTOP="$(pwd)/AppDir/legcord.desktop"
export ICON="$(pwd)/AppDir/legcord.png"

# Bundle audio + OpenGL + Vulkan stacks (Legcord uses all of them)
export DEPLOY_PULSE=1
export DEPLOY_OPENGL=1
export DEPLOY_VULKAN=1

# Deploy every binary in AppDir/bin/ -- including the wrapper AND the real
# Electron binary -- so sharun's strace can find every dlopened lib of both.
# Also bundle jq, libatomic and libappindicator3 (same as Discord-AppImage).
quick-sharun \
    ./AppDir/bin/*         \
    /usr/bin/jq            \
    /usr/lib/libatomic.so* \
    /usr/lib/libappindicator3.so*

# Generate the final AppImage (uruntime + DwarFS squash, 0-requirements)
quick-sharun --make-appimage

# ---------------------------------------------------------------------------
# STEP 6: Verify the build (only smoke-test the binary, do not run the GUI)
# ---------------------------------------------------------------------------
echo ""
echo "=== STEP 6: Verify bundled libc + ld-linux ==="

APPIMAGE_PATH=$(ls ./dist/*${ARCH}.AppImage 2>/dev/null | head -1)
if [ -z "$APPIMAGE_PATH" ]; then
    echo "ERROR: AppImage not found in ./dist/"
    exit 1
fi

echo "AppImage: $APPIMAGE_PATH ($(ls -lh "$APPIMAGE_PATH" | awk '{print $5}'))"

# Extract to a temp dir to verify the dynamic linker and libc are bundled
rm -rf /tmp/squashfs-root
( cd /tmp && "$APPIMAGE_PATH" --appimage-extract >/dev/null 2>&1 ) || \
    ( cd /tmp && chmod +x "$APPIMAGE_PATH" && ./"$(basename "$APPIMAGE_PATH")" --appimage-extract >/dev/null 2>&1 )

if [ -d /tmp/squashfs-root ]; then
    echo "Bundled dynamic linker:"
    find /tmp/squashfs-root -maxdepth 3 \( -name 'ld-linux*.so*' -o -name 'ld-musl*.so*' \) -exec ls -la {} \; 2>/dev/null | head -5
    echo "Bundled libc:"
    find /tmp/squashfs-root -maxdepth 4 -name 'libc.so*' -o -name 'libc.musl*' 2>/dev/null | head -5
    echo "Bundled wrapper:"
    ls -la /tmp/squashfs-root/bin/legcord 2>/dev/null || ls -la /tmp/squashfs-root/shared/bin/legcord 2>/dev/null || true
    rm -rf /tmp/squashfs-root
else
    echo "WARN: Could not extract AppImage for verification (FUSE may be unavailable in CI)"
fi

echo ""
echo "=== Build complete ==="
echo "AppImage: $(ls -lh ./dist/*.AppImage | awk '{print $5, $9}')"
echo "Version: $VERSION"
echo "Zsync:   $(ls ./dist/*.zsync 2>/dev/null || echo 'not found')"
echo "Sha256:  $(ls ./dist/*.sha256 2>/dev/null || echo 'not found')"
