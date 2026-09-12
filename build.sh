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
# This script is x86_64 only. If you need aarch64/armv7l, fork and adjust.
ARCH="x86_64"
LEGCORD_ARCH_DIR="linux-x64"
ASSET_PATTERN="linux-x64.tar.gz"
DEB_ARCH_PATTERN="amd64"

LEGCORD_REPO="Legcord/Legcord"
LEGCORD_API="https://api.github.com/repos/${LEGCORD_REPO}/releases/latest"

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
# NOTE: 'ar' is provided by 'binutils' which is part of 'base-devel' (already
# installed by anylinux-setup-action). Do NOT add it to the list — pacman will
# abort with "target not found: ar" because there is no standalone 'ar' pkg.
pacman -Syu --noconfirm \
    wget \
    strace \
    jq \
    brotli \
    libappindicator-gtk3 \
    libatomic \
    libva-intel-driver

# Debloated packages: recortan libLLVM, mesa, vulkan, Qt, GTK, libicudata
# hasta ~50 MiB en AppImages que usan GPU (frente a >200 MiB sin recortar)
get-debloated-pkgs --add-mesa --prefer-nano
get-debloated-pkgs --add-common --prefer-nano intel-media-driver-mini

# ---------------------------------------------------------------------------
# STEP 2: Download Legcord release metadata (tarball + .deb URLs)
# ---------------------------------------------------------------------------
echo ""
echo "=== STEP 2: Download Legcord release metadata ==="

RELEASE_JSON=$(wget -q --header="User-Agent: legcord-appimage" "$LEGCORD_API" -O -)
VERSION=$(echo "$RELEASE_JSON" | jq -r '.tag_name | ltrimstr("v")')

TARBALL_URL=$(echo "$RELEASE_JSON" \
    | jq -r --arg pat "$ASSET_PATTERN" \
        '.assets[] | select(.name | endswith($pat)) | .browser_download_url' \
    | head -1)

DEB_URL=$(echo "$RELEASE_JSON" \
    | jq -r --arg pat "$DEB_ARCH_PATTERN" \
        '.assets[] | select(.name | endswith(".deb")) | select(.name | contains($pat)) | .browser_download_url' \
    | head -1)

if [ -z "$TARBALL_URL" ] || [ "$TARBALL_URL" = "null" ]; then
    echo "ERROR: Could not find tarball asset '*$ASSET_PATTERN'"
    echo "$RELEASE_JSON" | jq '.assets[].name'
    exit 1
fi
if [ -z "$DEB_URL" ] || [ "$DEB_URL" = "null" ]; then
    echo "ERROR: Could not find .deb asset containing '$DEB_ARCH_PATTERN'"
    echo "$RELEASE_JSON" | jq '.assets[].name'
    exit 1
fi

echo "Latest Legcord version: $VERSION"
echo "Tarball URL: $TARBALL_URL"
echo "Deb URL:     $DEB_URL"

# ---------------------------------------------------------------------------
# STEP 3: Download .deb and extract icons + desktop file (icons are NOT in
# the tarball, only in the .deb package). We extract the .deb first so the
# icon search in STEP 5 finds them at /usr/share/icons/hicolor/...
# ---------------------------------------------------------------------------
echo ""
echo "=== STEP 3: Download .deb and extract icons + desktop file ==="

TMP_DEB=/tmp/legcord.deb
echo "Downloading .deb..."
wget -q "$DEB_URL" -O "$TMP_DEB"
ls -lh "$TMP_DEB"

# Extract data.tar.xz from the .deb (ar x writes to current directory)
WORK_DIR=$(mktemp -d)
( cd "$WORK_DIR" && ar x "$TMP_DEB" data.tar.xz )

if [ ! -f "$WORK_DIR/data.tar.xz" ]; then
    echo "ERROR: Failed to extract data.tar.xz from .deb"
    exit 1
fi

# Extract icons + desktop file to the system root (CI runs as root)
echo "Extracting icons + desktop file to /usr/share ..."
tar -xJf "$WORK_DIR/data.tar.xz" -C / \
    ./usr/share/applications/legcord.desktop \
    ./usr/share/icons/hicolor 2>/dev/null || true

rm -rf "$WORK_DIR" "$TMP_DEB"

# Verify extraction succeeded
if [ ! -f /usr/share/applications/legcord.desktop ]; then
    echo "ERROR: legcord.desktop not extracted to /usr/share/applications/"
    exit 1
fi
ICON_COUNT=$(find /usr/share/icons/hicolor -name "legcord.png" 2>/dev/null | wc -l)
if [ "$ICON_COUNT" -eq 0 ]; then
    echo "ERROR: No legcord.png icons extracted"
    exit 1
fi
echo "Extracted $ICON_COUNT icons + desktop file"

# ---------------------------------------------------------------------------
# STEP 4: Download and extract the Legcord tarball (binaries + Electron)
# ---------------------------------------------------------------------------
echo ""
echo "=== STEP 4: Download Legcord tarball ==="

mkdir -p ./AppDir/bin
echo "Downloading tarball..."
wget -q "$TARBALL_URL" -O - \
    | tar xzf - --strip-components=1 -C ./AppDir/bin

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
# STEP 5: Create wrapper script that injects Chromium flags
# ---------------------------------------------------------------------------
echo ""
echo "=== STEP 5: Create wrapper script with Chromium flags ==="

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
# STEP 6: Configure desktop file and icon for the AppDir
# ---------------------------------------------------------------------------
echo ""
echo "=== STEP 6: Configure desktop file and icon ==="

# Pick the highest-resolution icon
ICON_SRC=""
for size in 512x512 256x256 128x128 64x64 48x48 32x32; do
    candidate="/usr/share/icons/hicolor/${size}/apps/legcord.png"
    if [ -f "$candidate" ]; then
        ICON_SRC="$candidate"
        break
    fi
done

if [ -z "$ICON_SRC" ]; then
    echo "ERROR: No legcord.png icon found after .deb extraction"
    exit 1
fi

# Patch the system .desktop file to point inside the AppDir.
# - Main Exec= line points to /opt/Legcord/legcord -> replace with just 'legcord'
# - Action Exec= lines use 'AppRun' as the binary name -> replace with 'legcord'
#   preserving the action-specific args (--mute, --deafen, --leave, --opensettings)
sed \
    -e 's|^Exec=/opt/Legcord/legcord|Exec=legcord|' \
    -e 's|^Exec=AppRun |Exec=legcord |g' \
    -e 's|^Icon=.*|Icon=legcord|' \
    /usr/share/applications/legcord.desktop > ./AppDir/legcord.desktop

# Copy icon to AppDir root (quick-sharun looks for it there) and .DirIcon
cp "$ICON_SRC" ./AppDir/legcord.png
cp "$ICON_SRC" ./AppDir/.DirIcon

echo "Desktop file: $(ls -la ./AppDir/legcord.desktop | awk '{print $5, $9}')"
echo "Icon:         $ICON_SRC"
echo "AppDir Icon:  $(ls -la ./AppDir/legcord.png | awk '{print $5, $9}')"

# ---------------------------------------------------------------------------
# STEP 7: Package with quick-sharun
# ---------------------------------------------------------------------------
echo ""
echo "=== STEP 7: Package with quick-sharun ==="

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
# STEP 8: Verify the build (smoke-test the binary, do not run the GUI)
# ---------------------------------------------------------------------------
# IMPORTANT: This step MUST be non-fatal. The AppImage is already built in
# STEP 7; this is just a sanity check. If verification fails (e.g., FUSE
# unavailable, or extract-and-run also fails), we must NOT exit with non-zero
# because that would skip the artifact upload in the next CI step.
echo ""
echo "=== STEP 8: Verify bundled libc + ld-linux ==="

APPIMAGE_PATH=$(ls ./dist/*${ARCH}.AppImage 2>/dev/null | head -1)
if [ -z "$APPIMAGE_PATH" ]; then
    echo "ERROR: AppImage not found in ./dist/ -- this is a real build failure"
    ls -la ./dist/ 2>/dev/null || true
    exit 1
fi

# Convert to ABSOLUTE path before any 'cd' to /tmp (relative paths break there)
APPIMAGE_ABS=$(readlink -f "$APPIMAGE_PATH")
echo "AppImage: $APPIMAGE_ABS ($(ls -lh "$APPIMAGE_ABS" | awk '{print $5}'))"

# Make sure the AppImage is executable (uruntime needs +x)
chmod +x "$APPIMAGE_ABS" 2>/dev/null || true

# Extract to a temp dir to verify the dynamic linker and libc are bundled.
# Everything here is wrapped in 'set +e' so a failure does NOT exit the build.
set +e
rm -rf /tmp/squashfs-root
( cd /tmp && "$APPIMAGE_ABS" --appimage-extract >/dev/null 2>&1 )

if [ -d /tmp/squashfs-root ]; then
    echo "Bundled dynamic linker:"
    find /tmp/squashfs-root -maxdepth 3 \( -name 'ld-linux*.so*' -o -name 'ld-musl*.so*' \) -exec ls -la {} \; 2>/dev/null | head -5
    echo "Bundled libc:"
    find /tmp/squashfs-root -maxdepth 4 \( -name 'libc.so*' -o -name 'libc.musl*' \) 2>/dev/null | head -5
    echo "Bundled wrapper:"
    ls -la /tmp/squashfs-root/bin/legcord 2>/dev/null || ls -la /tmp/squashfs-root/shared/bin/legcord 2>/dev/null || true
    rm -rf /tmp/squashfs-root
else
    echo "WARN: Could not extract AppImage for verification (FUSE may be unavailable in CI)."
    echo "      The AppImage was still built successfully -- this is just a verification skip."
fi
set -e

echo ""
echo "=== Build complete ==="
echo "AppImage: $(ls -lh ./dist/*.AppImage | awk '{print $5, $9}')"
echo "Version: $VERSION"
echo "Zsync:   $(ls ./dist/*.zsync 2>/dev/null || echo 'not found')"
echo "Sha256:  $(ls ./dist/*.sha256 2>/dev/null || echo 'not found')"
