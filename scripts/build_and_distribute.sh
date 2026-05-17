#!/usr/bin/env bash
# Usage:
#   NOTARIZE_PASSWORD="<app-specific-password>" ./scripts/build_and_distribute.sh
set -euo pipefail

# ── config ────────────────────────────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Groots"
BUNDLE_ID="com.rce-studio.groots"
TEAM_ID="B3UPYA8K4D"
APPLE_ID="raul@rce-studio.com"
IDENTITY="Developer ID Application: Raúl Castro Estévez (${TEAM_ID})"

SRCROOT="${REPO_ROOT}/groots_app/macos"
WORKSPACE="${REPO_ROOT}/groots_app/macos/Runner.xcworkspace"
SCHEME="Runner"
EXPORT_OPTS="${REPO_ROOT}/scripts/ExportOptions.plist"

DIST="${REPO_ROOT}/dist"
ARCHIVE="${DIST}/groots.xcarchive"
EXPORT_DIR="${DIST}/export"
APP="${EXPORT_DIR}/groots_app.app"
STAGED_APP="${DIST}/staging/${APP_NAME}.app"
ZIP="${DIST}/groots_app_notarize.zip"
DMG="${DIST}/${APP_NAME}.dmg"
BACKGROUND="${REPO_ROOT}/scripts/dmg_background.png"
VOLICON="${SRCROOT}/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png"

NOTARIZE_PASSWORD="${NOTARIZE_PASSWORD:-}"
if [[ -z "$NOTARIZE_PASSWORD" ]]; then
  echo "error: set NOTARIZE_PASSWORD to your app-specific password"
  echo "       NOTARIZE_PASSWORD='xxxx-xxxx-xxxx-xxxx' ./scripts/build_and_distribute.sh"
  exit 1
fi

mkdir -p "${DIST}"

# ── 1. build ──────────────────────────────────────────────────────────────────
echo "▶ Building Flutter macOS release..."
cd "${REPO_ROOT}/groots_app"
flutter build macos --release --target lib/production.dart
cd "${REPO_ROOT}"

# ── 2. archive ────────────────────────────────────────────────────────────────
echo "▶ Archiving..."
rm -rf "${ARCHIVE}"
xcodebuild archive \
  -workspace "${WORKSPACE}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -archivePath "${ARCHIVE}" \
  -destination "generic/platform=macOS" \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="${TEAM_ID}" \
  | xcpretty 2>/dev/null || true

# ── 3. export ─────────────────────────────────────────────────────────────────
echo "▶ Exporting..."
rm -rf "${EXPORT_DIR}"
xcodebuild -exportArchive \
  -archivePath "${ARCHIVE}" \
  -exportPath "${EXPORT_DIR}" \
  -exportOptionsPlist "${EXPORT_OPTS}"

# ── 4. re-sign nested code with hardened runtime ──────────────────────────────
echo "▶ Re-signing nested binaries..."

codesign --force --options runtime \
  --sign "${IDENTITY}" \
  --entitlements "${SRCROOT}/KuboHelper/ipfs.entitlements" \
  "${APP}/Contents/XPCServices/KuboHelper.xpc/Contents/Resources/ipfs"

codesign --force --options runtime \
  --sign "${IDENTITY}" \
  --entitlements "${SRCROOT}/KuboHelper/KuboHelper-Release.entitlements" \
  "${APP}/Contents/XPCServices/KuboHelper.xpc/Contents/MacOS/KuboHelper"

codesign --force --options runtime \
  --sign "${IDENTITY}" \
  --entitlements "${SRCROOT}/KuboHelper/KuboHelper-Release.entitlements" \
  "${APP}/Contents/XPCServices/KuboHelper.xpc"

codesign --force --options runtime \
  --sign "${IDENTITY}" \
  --entitlements "${SRCROOT}/Runner/Release.entitlements" \
  "${APP}"

echo "▶ Verifying signature..."
codesign --verify --deep --strict "${APP}" && echo "   Signature OK"

# ── 5. notarize .app ──────────────────────────────────────────────────────────
echo "▶ Zipping for notarization..."
rm -f "${ZIP}"
ditto -c -k --keepParent "${APP}" "${ZIP}"

echo "▶ Submitting to Apple Notarization (this takes ~1-2 min)..."
xcrun notarytool submit "${ZIP}" \
  --apple-id "${APPLE_ID}" \
  --team-id "${TEAM_ID}" \
  --password "${NOTARIZE_PASSWORD}" \
  --wait

echo "▶ Stapling .app..."
xcrun stapler staple "${APP}"

echo "▶ Gatekeeper check..."
spctl --assess --type exec --verbose "${APP}"

rm -f "${ZIP}"

# ── 6. package into DMG ───────────────────────────────────────────────────────
echo "▶ Generating DMG background..."
python3 "${REPO_ROOT}/scripts/generate_dmg_background.py" "${BACKGROUND}"

echo "▶ Staging app..."
rm -rf "${DIST}/staging"
mkdir -p "${DIST}/staging"
cp -R "${APP}" "${STAGED_APP}"

if ! command -v create-dmg &>/dev/null; then
  echo "Installing create-dmg..."
  brew install create-dmg
fi

echo "▶ Building DMG..."
rm -f "${DMG}"
create-dmg \
  --volname "${APP_NAME}" \
  --volicon "${VOLICON}" \
  --background "${BACKGROUND}" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 128 \
  --icon "${APP_NAME}.app" 180 185 \
  --hide-extension "${APP_NAME}.app" \
  --app-drop-link 480 185 \
  --no-internet-enable \
  "${DMG}" \
  "${DIST}/staging"

rm -rf "${DIST}/staging"

# ── 7. notarize DMG ───────────────────────────────────────────────────────────
echo "▶ Submitting DMG to Apple Notarization..."
xcrun notarytool submit "${DMG}" \
  --apple-id "${APPLE_ID}" \
  --team-id "${TEAM_ID}" \
  --password "${NOTARIZE_PASSWORD}" \
  --wait

echo "▶ Stapling DMG..."
xcrun stapler staple "${DMG}"

# ── done ──────────────────────────────────────────────────────────────────────
echo ""
echo "✓ Done! Distributable ready at:"
echo "  ${DMG}"
