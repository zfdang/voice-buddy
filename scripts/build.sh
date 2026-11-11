#!/usr/bin/env bash
#
# Voice Buddy - Local Build and Signing Script
# Builds Voice Buddy into `dist/Voice Buddy.app` and automatically signs it with
# the local private development certificate ("Voice Buddy Local Development").
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

# Ensure Xcode tools are selected if CommandLineTools lacks XCTest/Metal
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

# Default configuration
BUILD_CONFIG="release"
DO_PACKAGE="false"
DO_OPEN="false"
CUSTOM_VERSION=""
CUSTOM_IDENTITY="${VOICE_BUDDY_SIGN_IDENTITY:-}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [options] [debug|release]

Build Voice Buddy macOS application into dist/Voice Buddy.app and sign with private certificate.

Options:
  debug, --debug        Build in debug configuration (faster compilation)
  release, --release    Build in release configuration (optimized, default)
  -p, --package         Create distribution DMG, ZIP, and SHA256SUMS.txt in dist/
  -o, --open            Launch dist/Voice Buddy.app after successful build
  -v, --version <ver>   Specify application bundle version (e.g. 0.1.0)
  -s, --sign <id>       Override codesigning identity
  --strict-signing      Enforce non-adhoc codesigning certificate (fails if ad-hoc)
  --allow-adhoc         Explicitly allow ad-hoc signing even in strict mode
  -h, --help            Show this help message

Output:
  dist/Voice Buddy.app
EOF
    exit 0
}

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        debug|--debug)
            BUILD_CONFIG="debug"
            shift
            ;;
        release|--release)
            BUILD_CONFIG="release"
            shift
            ;;
        -p|--package|package)
            DO_PACKAGE="true"
            shift
            ;;
        -o|--open)
            DO_OPEN="true"
            shift
            ;;
        -v|--version)
            CUSTOM_VERSION="$2"
            shift 2
            ;;
        -s|--sign)
            CUSTOM_IDENTITY="$2"
            shift 2
            ;;
        --strict-signing)
            STRICT_SIGNING="true"
            shift
            ;;
        --allow-adhoc)
            ALLOW_ADHOC="true"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            if [[ "$1" =~ ^v?[0-9]+(\.[0-9]+)* ]]; then
                CUSTOM_VERSION="$1"
                shift
            else
                echo "Unknown argument: $1" >&2
                echo "Run '$0 --help' for usage." >&2
                exit 2
            fi
            ;;
    esac
done

# Resolve version
if [ -n "${CUSTOM_VERSION}" ]; then
    RAW_VERSION="${CUSTOM_VERSION}"
else
    # Try git tag, fallback to 0.1.0
    GIT_TAG="$(git describe --tags --exact-match 2>/dev/null || true)"
    if [ -n "${GIT_TAG}" ]; then
        RAW_VERSION="${GIT_TAG}"
    else
        RAW_VERSION="0.1.0"
    fi
fi
BUNDLE_VERSION="${RAW_VERSION#v}"

# Determine codesigning identity
# Priority:
# 1. Explicit argument / VOICE_BUDDY_SIGN_IDENTITY
# 2. "Voice Buddy Local Development" in Keychain
# 3. Any valid codesigning identity in Keychain
# 4. Ad-hoc fallback (-)
if [ -n "${CUSTOM_IDENTITY}" ]; then
    SIGN_IDENTITY="${CUSTOM_IDENTITY}"
    SIGN_REASON="explicitly specified"
elif security find-identity -v -p codesigning 2>/dev/null | grep -q '"Voice Buddy Local Development"'; then
    SIGN_IDENTITY="Voice Buddy Local Development"
    SIGN_REASON="automatically detected private development certificate"
else
    DISCOVERED_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/"/ {print $2; exit}' || true)"
    if [ -n "${DISCOVERED_IDENTITY}" ]; then
        SIGN_IDENTITY="${DISCOVERED_IDENTITY}"
        SIGN_REASON="detected codesigning certificate in keychain"
    else
        SIGN_IDENTITY="-"
        SIGN_REASON="ad-hoc signing (no keychain certificate found)"
    fi
fi

if [ "${STRICT_SIGNING:-false}" = "true" ] && [ "${SIGN_IDENTITY}" = "-" ] && [ "${ALLOW_ADHOC:-false}" != "true" ]; then
    echo "Error: Strict codesigning required, but no valid codesigning certificate was found in Keychain (resolved to ad-hoc '-')." >&2
    echo "Please configure a valid signing certificate in keychain or pass --allow-adhoc." >&2
    exit 1
fi

echo "=========================================================="
echo " Voice Buddy - Local Build"
echo "=========================================================="
echo " Configuration : ${BUILD_CONFIG}"
echo " Bundle Version: ${BUNDLE_VERSION}"
echo " Signing ID    : ${SIGN_IDENTITY} (${SIGN_REASON})"
echo " Output Target : dist/Voice Buddy.app"
echo " Developer Dir : ${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || echo 'default')}"
echo "=========================================================="

# 1. Build Swift Package
echo ""
echo "==> Step 1/4: Compiling Swift Package (${BUILD_CONFIG})..."
swift build -c "${BUILD_CONFIG}" -j 4

# 2. Build MLX Metal Library
echo ""
echo "==> Step 2/4: Building Metal Library (mlx.metallib)..."
BUILD_DIR="${ROOT_DIR}/.build" bash "${ROOT_DIR}/.build/checkouts/speech-swift/scripts/build_mlx_metallib.sh" "${BUILD_CONFIG}"

# 3. Assemble App Bundle
echo ""
echo "==> Step 3/4: Assembling dist/Voice Buddy.app..."
mkdir -p "${ROOT_DIR}/dist"
if [ "${DO_PACKAGE}" != "true" ]; then
    rm -f "${ROOT_DIR}/dist"/*.dmg "${ROOT_DIR}/dist"/*.zip "${ROOT_DIR}/dist"/SHA256SUMS.txt
fi
APP_BUNDLE="${ROOT_DIR}/dist/Voice Buddy.app"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources" "${APP_BUNDLE}/Contents/Frameworks"

SPM_OUT="${ROOT_DIR}/.build/${BUILD_CONFIG}"
if [ ! -f "${SPM_OUT}/VoiceBuddy" ] && [ -f "${ROOT_DIR}/.build/arm64-apple-macosx/${BUILD_CONFIG}/VoiceBuddy" ]; then
    SPM_OUT="${ROOT_DIR}/.build/arm64-apple-macosx/${BUILD_CONFIG}"
fi

cp "${SPM_OUT}/VoiceBuddy" "${APP_BUNDLE}/Contents/MacOS/VoiceBuddy"
if [ -d "${SPM_OUT}/VoiceBuddy_VoiceBuddyApp.bundle" ]; then
    cp -R "${SPM_OUT}/VoiceBuddy_VoiceBuddyApp.bundle" "${APP_BUNDLE}/Contents/Resources/" 2>/dev/null || true
fi
cp "${SPM_OUT}/mlx.metallib" "${APP_BUNDLE}/Contents/MacOS/mlx.metallib"

# Copy additional resource bundles (LaunchAtLogin, KeyboardShortcuts)
for b in "${SPM_OUT}"/*.bundle; do
    if [ -d "${b}" ]; then
        cp -R "${b}" "${APP_BUNDLE}/Contents/Resources/" 2>/dev/null || true
    fi
done

# Copy dynamic frameworks (Sparkle.framework)
if [ -d "${SPM_OUT}/Sparkle.framework" ]; then
    cp -R "${SPM_OUT}/Sparkle.framework" "${APP_BUNDLE}/Contents/Frameworks/"
fi
install_name_tool -add_rpath "@executable_path/../Frameworks" "${APP_BUNDLE}/Contents/MacOS/VoiceBuddy" 2>/dev/null || true

# Ensure AppIcon.icns exists
ICON_SRC="${ROOT_DIR}/Sources/VoiceBuddyApp/Resources/AppIcon.icns"
if [ ! -f "${ICON_SRC}" ] || [ "${ROOT_DIR}/Sources/VoiceBuddyApp/Resources/mascot.png" -nt "${ICON_SRC}" ]; then
    echo "Generating AppIcon.icns from mascot.png..."
    TMP_ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "${TMP_ICONSET}"
    PNG_SRC="${ROOT_DIR}/Sources/VoiceBuddyApp/Resources/mascot.png"
    sips -z 16 16     "${PNG_SRC}" --out "${TMP_ICONSET}/icon_16x16.png" >/dev/null 2>&1 || true
    sips -z 32 32     "${PNG_SRC}" --out "${TMP_ICONSET}/icon_16x16@2x.png" >/dev/null 2>&1 || true
    sips -z 32 32     "${PNG_SRC}" --out "${TMP_ICONSET}/icon_32x32.png" >/dev/null 2>&1 || true
    sips -z 64 64     "${PNG_SRC}" --out "${TMP_ICONSET}/icon_32x32@2x.png" >/dev/null 2>&1 || true
    sips -z 128 128   "${PNG_SRC}" --out "${TMP_ICONSET}/icon_128x128.png" >/dev/null 2>&1 || true
    sips -z 256 256   "${PNG_SRC}" --out "${TMP_ICONSET}/icon_128x128@2x.png" >/dev/null 2>&1 || true
    sips -z 256 256   "${PNG_SRC}" --out "${TMP_ICONSET}/icon_256x256.png" >/dev/null 2>&1 || true
    sips -z 512 512   "${PNG_SRC}" --out "${TMP_ICONSET}/icon_256x256@2x.png" >/dev/null 2>&1 || true
    sips -z 512 512   "${PNG_SRC}" --out "${TMP_ICONSET}/icon_512x512.png" >/dev/null 2>&1 || true
    sips -z 1024 1024 "${PNG_SRC}" --out "${TMP_ICONSET}/icon_512x512@2x.png" >/dev/null 2>&1 || true
    iconutil -c icns "${TMP_ICONSET}" -o "${ICON_SRC}" 2>/dev/null || true
    rm -rf "$(dirname "${TMP_ICONSET}")"
fi

if [ -f "${ICON_SRC}" ]; then
    cp "${ICON_SRC}" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi
if [ -d "${ROOT_DIR}/Sources/VoiceBuddyApp/Resources" ]; then
    cp -R "${ROOT_DIR}/Sources/VoiceBuddyApp/Resources/"* "${APP_BUNDLE}/Contents/Resources/" 2>/dev/null || true
fi

cat > "${APP_BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.voicebuddy.app</string>
    <key>CFBundleExecutable</key>
    <string>VoiceBuddy</string>
    <key>CFBundleName</key>
    <string>Voice Buddy</string>
    <key>CFBundleDisplayName</key>
    <string>Voice Buddy</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>${BUNDLE_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUNDLE_VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Voice Buddy uses the microphone to transcribe your speech locally with on-device AI.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Voice Buddy uses Apple Speech to provide fast, built-in on-device dictation.</string>
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/zfdang/voice-buddy/main/appcast.xml</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUPublicEDKey</key>
    <string>${SPARKLE_PUBLIC_EDKEY:-DFo0eXPztCxiR8+rSEIV/Odz4I9eT8p1UcjFSUaAqoo=}</string>
</dict>
</plist>
PLIST

touch "${APP_BUNDLE}"

# 4. Code Signing
echo ""
echo "==> Step 4/4: Signing ${APP_BUNDLE} with '${SIGN_IDENTITY}'..."

RUNTIME_FLAGS=()
if [[ "${SIGN_IDENTITY}" == *"Developer ID Application"* ]] || [ "${HARDENED_RUNTIME:-false}" = "true" ]; then
    RUNTIME_FLAGS=(--options runtime)
fi

sign_component() {
    local target="$1"
    shift
    local extra_args=("$@")
    if [ "${SIGN_IDENTITY}" = "-" ]; then
        codesign --force --sign - ${extra_args[@]+"${extra_args[@]}"} "${target}"
    else
        local flags=(--force ${RUNTIME_FLAGS[@]+"${RUNTIME_FLAGS[@]}"} ${extra_args[@]+"${extra_args[@]}"})
        if ! codesign "${flags[@]}" --timestamp --sign "${SIGN_IDENTITY}" "${target}" 2>/dev/null; then
            echo "Note: Secure timestamp signing failed for $(basename "${target}"); falling back to timestamp=none."
            codesign "${flags[@]}" --timestamp=none --sign "${SIGN_IDENTITY}" "${target}"
        fi
    fi
}

# Sign embedded frameworks and XPC services inside-out (avoiding --deep which taints helper services with app entitlements)
SPARKLE_FRAMEWORK="${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework"
if [ -d "${SPARKLE_FRAMEWORK}" ]; then
    echo "Signing embedded Sparkle components from inside out..."
    SPARKLE_VER="${SPARKLE_FRAMEWORK}/Versions/Current"
    if [ ! -d "${SPARKLE_VER}" ]; then
        SPARKLE_VER="${SPARKLE_FRAMEWORK}/Versions/B"
    fi
    if [ -d "${SPARKLE_VER}/XPCServices/Installer.xpc" ]; then
        sign_component "${SPARKLE_VER}/XPCServices/Installer.xpc"
    fi
    if [ -d "${SPARKLE_VER}/XPCServices/Downloader.xpc" ]; then
        sign_component "${SPARKLE_VER}/XPCServices/Downloader.xpc" --preserve-metadata=entitlements
    fi
    if [ -f "${SPARKLE_VER}/Autoupdate" ]; then
        sign_component "${SPARKLE_VER}/Autoupdate"
    fi
    if [ -d "${SPARKLE_VER}/Updater.app" ]; then
        sign_component "${SPARKLE_VER}/Updater.app"
    fi
    sign_component "${SPARKLE_FRAMEWORK}"
fi

# Sign any other embedded frameworks or dylibs
if [ -d "${APP_BUNDLE}/Contents/Frameworks" ]; then
    find "${APP_BUNDLE}/Contents/Frameworks" -mindepth 1 -maxdepth 1 ! -name "Sparkle.framework" | while read -r fw; do
        if [ -e "${fw}" ]; then
            sign_component "${fw}"
        fi
    done
fi

# Sign embedded binaries / metal libraries in Contents/MacOS before root bundle
if [ -f "${APP_BUNDLE}/Contents/MacOS/mlx.metallib" ]; then
    sign_component "${APP_BUNDLE}/Contents/MacOS/mlx.metallib"
fi

# Finally, sign the main application bundle at root with entitlements (DO NOT pass --deep here)
ENTITLEMENTS_PATH="${ROOT_DIR}/VoiceBuddy.entitlements"
MAIN_FLAGS=()
if [ -f "${ENTITLEMENTS_PATH}" ]; then
    MAIN_FLAGS+=(--entitlements "${ENTITLEMENTS_PATH}")
fi
sign_component "${APP_BUNDLE}" ${MAIN_FLAGS[@]+"${MAIN_FLAGS[@]}"}

echo "Verifying code signature..."
codesign --verify --deep --strict "${APP_BUNDLE}"
codesign -dvvv "${APP_BUNDLE}" 2>&1 | grep -E "(Identifier|Format|Authority|TeamIdentifier|Signature)" || true

echo "Smoke testing application binary startup..."
python3 -c "
import subprocess, sys

proc = subprocess.Popen(['${APP_BUNDLE}/Contents/MacOS/VoiceBuddy'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
try:
    stdout, stderr = proc.communicate(timeout=1.5)
    if proc.returncode != 0:
        sys.stderr.write(f'Smoke test failed with returncode {proc.returncode}:\n{stderr.decode()}\n')
        sys.exit(1)
except subprocess.TimeoutExpired:
    proc.terminate()
    try:
        proc.wait(timeout=1)
    except subprocess.TimeoutExpired:
        proc.kill()
    print('Smoke test passed: binary launched cleanly without crash.')
"

if [ "${STRICT_SIGNING:-false}" = "true" ] && [ "${ALLOW_ADHOC:-false}" != "true" ]; then
    if codesign -dvvv "${APP_BUNDLE}" 2>&1 | grep -q "Signature=adhoc"; then
        echo "Error: Application bundle ${APP_BUNDLE} was signed with ad-hoc signature, failing strict signing check." >&2
        exit 1
    fi
fi

# Optional: Packaging
if [ "${DO_PACKAGE}" = "true" ]; then
    echo ""
    echo "==> Packaging distribution artifacts in dist/..."
    ZIP_NAME="Voice-Buddy-${RAW_VERSION}-macOS.zip"
    DMG_NAME="Voice-Buddy-${RAW_VERSION}-macOS.dmg"
    rm -f "${ROOT_DIR}/dist/${ZIP_NAME}" "${ROOT_DIR}/dist/${DMG_NAME}" "${ROOT_DIR}/dist/SHA256SUMS.txt"

    echo "Creating ${ZIP_NAME}..."
    ditto -c -k --keepParent "${APP_BUNDLE}" "${ROOT_DIR}/dist/${ZIP_NAME}"

    echo "Creating ${DMG_NAME}..."
    hdiutil create -volname "Voice Buddy" -srcfolder "${APP_BUNDLE}" -ov -format UDZO "${ROOT_DIR}/dist/${DMG_NAME}"

    echo "Generating checksums..."
    (cd "${ROOT_DIR}/dist" && shasum -a 256 "${ZIP_NAME}" "${DMG_NAME}" > SHA256SUMS.txt)
    cat "${ROOT_DIR}/dist/SHA256SUMS.txt"
fi

echo ""
echo "=========================================================="
echo " Build Succeeded!"
echo " App Bundle: ${APP_BUNDLE}"
echo " Signed As : ${SIGN_IDENTITY}"
echo "=========================================================="

if [ "${DO_OPEN}" = "true" ]; then
    echo "Launching Voice Buddy..."
    open "${APP_BUNDLE}"
fi
