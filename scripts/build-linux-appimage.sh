#!/bin/bash
# Builds the Groots Flutter Linux app in production mode and packages it as
# an AppImage. Run from any directory — paths are resolved relative to this script.
#
# Usage:
#   ./scripts/build-linux-appimage.sh
#
# Output:
#   dist/Groots-<version>-x86_64.AppImage
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="$ROOT_DIR/groots_app"
DIST_DIR="$ROOT_DIR/dist"
APPDIR="$DIST_DIR/AppDir"
APPIMAGETOOL="$DIST_DIR/appimagetool"

# ── 1. Resolve version ────────────────────────────────────────────────────────
VERSION=$(grep '^version:' "$APP_DIR/pubspec.yaml" | awk '{print $2}' | cut -d'+' -f1)
OUTPUT="$DIST_DIR/Groots-$VERSION-x86_64.AppImage"
echo "==> Building Groots $VERSION"

# ── 2. Verify Kubo binary is present ─────────────────────────────────────────
KUBO_BIN="$APP_DIR/linux/bin/ipfs"
if [ ! -f "$KUBO_BIN" ]; then
  echo "ERROR: Kubo binary not found at linux/bin/ipfs"
  echo "       Download it with:"
  echo "       cd groots_app/linux/bin && wget https://dist.ipfs.tech/kubo/v0.41.0/kubo_v0.41.0_linux-amd64.tar.gz"
  echo "       tar -xzf kubo_v0.41.0_linux-amd64.tar.gz kubo/ipfs && mv kubo/ipfs ./ipfs && rm -rf kubo *.tar.gz"
  exit 1
fi

# ── 3. Download appimagetool if needed ────────────────────────────────────────
mkdir -p "$DIST_DIR"
if [ ! -f "$APPIMAGETOOL" ]; then
  echo "==> Downloading appimagetool..."
  wget -q --show-progress \
    -O "$APPIMAGETOOL" \
    "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
  chmod +x "$APPIMAGETOOL"
fi

# ── 4. Flutter release build ──────────────────────────────────────────────────
echo "==> Flutter build linux --release"
cd "$APP_DIR"
flutter build linux --release --target lib/production.dart

BUNDLE="$APP_DIR/build/linux/x64/release/bundle"

# ── 5. Assemble AppDir ────────────────────────────────────────────────────────
echo "==> Assembling AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR"

# Copy the full Flutter bundle (executable + lib/ + data/)
cp -r "$BUNDLE/." "$APPDIR/"

# Icon (sourced from the macOS app icon set)
cp "$APP_DIR/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png" \
   "$APPDIR/groots.png"

# Desktop entry required by AppImage spec
cat > "$APPDIR/groots.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Groots
Exec=groots
Icon=groots
Categories=Audio;Music;
Comment=Decentralized personal music streaming
StartupWMClass=groots
EOF

# AppRun: set library path so Flutter's bundled libs are found
cat > "$APPDIR/AppRun" << 'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$HERE/groots" "$@"
EOF
chmod +x "$APPDIR/AppRun"

# ── 6. Package AppImage ───────────────────────────────────────────────────────
echo "==> Packaging AppImage → $OUTPUT"
ARCH=x86_64 "$APPIMAGETOOL" --appimage-extract-and-run "$APPDIR" "$OUTPUT"

echo ""
echo "Done: $OUTPUT"
echo "Size: $(du -sh "$OUTPUT" | cut -f1)"
