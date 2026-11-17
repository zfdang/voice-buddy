#!/usr/bin/env bash
# Sign an already-built release without exporting or replacing the existing key.
set -euo pipefail

: "${TAG:?Release tag is required}"
: "${SPARKLE_ED_KEY:?Existing Sparkle signing key is required}"
: "${GH_TOKEN:?Public release read access is required}"
if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Expected a stable v<major>.<minor>.<patch> tag" >&2
    exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
archive="Voice-Buddy-${TAG}-macOS.zip"
mkdir -p "$work_dir/archives" "$work_dir/sparkle" dist

gh release download "$TAG" --repo zfdang/voice-buddy \
    --pattern "$archive" --pattern SHA256SUMS.txt --dir "$work_dir/archives"
# Validate only this ZIP; the checksum manifest also lists a DMG not used here.
python3 - "$work_dir/archives" "$archive" <<'PYTHON'
import hashlib, pathlib, sys
folder, name = pathlib.Path(sys.argv[1]), sys.argv[2]
entries = dict(line.split(maxsplit=1)[::-1] for line in (folder / 'SHA256SUMS.txt').read_text().splitlines())
assert hashlib.sha256((folder / name).read_bytes()).hexdigest() == entries[name], 'ZIP checksum mismatch'
PYTHON

ditto -x -k "$work_dir/archives/$archive" "$work_dir/app"
plist="$work_dir/app/Voice Buddy.app/Contents/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
[[ "$version" == "${TAG#v}" ]] || { echo "App version does not match release tag" >&2; exit 1; }
codesign --verify --deep --strict "$work_dir/app/Voice Buddy.app"
embedded_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist")"
# Pass the secret through stdin, never a process argument or a generated file.
derived_key="$(printf '%s' "$SPARKLE_ED_KEY" | swift -e '
import CryptoKit
import Foundation
let encoded = FileHandle.standardInput.readDataToEndOfFile()
guard let raw = Data(base64Encoded: encoded),
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else { exit(1) }
print(key.publicKey.rawRepresentation.base64EncodedString())
')"
[[ "$derived_key" == "$embedded_key" ]] || { echo "Signing key does not match installed-client public key" >&2; exit 1; }

gh release download 2.10.1 --repo sparkle-project/Sparkle \
    --pattern Sparkle-2.10.1.tar.xz --dir "$work_dir/sparkle"
tar -xf "$work_dir/sparkle/Sparkle-2.10.1.tar.xz" -C "$work_dir/sparkle"
curl -fsSL https://raw.githubusercontent.com/zfdang/voice-buddy/main/appcast.xml \
    -o "$work_dir/archives/appcast.xml"
printf '%s' "$SPARKLE_ED_KEY" | "$work_dir/sparkle/bin/generate_appcast" \
    --ed-key-file - --download-url-prefix "https://github.com/zfdang/voice-buddy/releases/download/${TAG}/" \
    "$work_dir/archives"
cp "$work_dir/archives/appcast.xml" dist/appcast.xml
python3 - dist/appcast.xml "$TAG" <<'PYTHON'
import sys, xml.etree.ElementTree as ET
ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
items = ET.parse(sys.argv[1]).findall('./channel/item')
item = next(i for i in items if i.findtext(ns + 'version') == sys.argv[2][1:])
assert item.find('enclosure').get(ns + 'edSignature'), 'Missing EdDSA signature'
print('Signed update feed verified for', sys.argv[2])
PYTHON
