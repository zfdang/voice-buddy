#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

action="${1:-release}"
case "$action" in
    debug|release) ;;
    *) echo "usage: $0 [debug|release] [version] [--package]" >&2; exit 2;;
esac

raw_version="${2:-0.1.0}"
bundle_version="${raw_version#v}"
do_package="${3:-}"

echo "Building Voice Buddy ($action mode, version $bundle_version)..."
swift build -c "$action" -j 4
BUILD_DIR="$PWD/.build" bash .build/checkouts/speech-swift/scripts/build_mlx_metallib.sh "$action"

app="dist/Voice Buddy.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/"$action"/VoiceBuddy "$app/Contents/MacOS/VoiceBuddy"
cp -R .build/"$action"/VoiceBuddy_VoiceBuddyApp.bundle "$app/Contents/Resources/"
cp .build/"$action"/mlx.metallib "$app/Contents/MacOS/mlx.metallib"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.voicebuddy.app</string>
<key>CFBundleExecutable</key><string>VoiceBuddy</string>
<key>CFBundleName</key><string>Voice Buddy</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${bundle_version}</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSMicrophoneUsageDescription</key><string>Voice Buddy uses the microphone to transcribe your speech locally.</string>
</dict></plist>
PLIST

if [ -z "${VOICE_BUDDY_SIGN_IDENTITY:-}" ]; then
    discovered="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/"/ {print $2; exit}' || true)"
    identity="${discovered:-Voice Buddy Local Development}"
else
    identity="$VOICE_BUDDY_SIGN_IDENTITY"
fi

echo "Signing $app with identity: $identity"
codesign --force --deep --timestamp=none --sign "$identity" "$app"
codesign --verify --deep --strict "$app"

if [ "$do_package" = "--package" ] || [ "$do_package" = "package" ]; then
    echo "Creating distribution packages for ${raw_version}..."
    zip_name="Voice-Buddy-${raw_version}-macOS.zip"
    dmg_name="Voice-Buddy-${raw_version}-macOS.dmg"
    rm -f "dist/${zip_name}" "dist/${dmg_name}" "dist/SHA256SUMS.txt"

    echo "Creating ${zip_name}..."
    ditto -c -k --keepParent "$app" "dist/${zip_name}"

    echo "Creating ${dmg_name}..."
    hdiutil create -volname "Voice Buddy" -srcfolder "$app" -ov -format UDZO "dist/${dmg_name}"

    echo "Generating checksums..."
    (cd dist && shasum -a 256 "${zip_name}" "${dmg_name}" > SHA256SUMS.txt)
    cat dist/SHA256SUMS.txt
fi
