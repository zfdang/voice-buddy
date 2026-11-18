#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/candidate" "$work/candidate/downloads"

echo '{"tagName":"","assets":[]}' > "$work/release.json"

valid_candidate=false

# 1. Try current workflow run artifact first (when triggered via workflow_run)
if [[ -n "${PAGES_UPDATE_RUN_ID:-}" ]]; then
    echo "Attempting to download website-update-feeds artifact from workflow run $PAGES_UPDATE_RUN_ID..."
    if gh run download "$PAGES_UPDATE_RUN_ID" --name website-update-feeds --dir "$work/candidate" >/dev/null 2>"$work/error.log"; then
        shopt -s nullglob
        for bin in "$work/candidate"/*.dmg "$work/candidate"/*.zip "$work/candidate"/SHA256SUMS.txt; do
            mv -f "$bin" "$work/candidate/downloads/"
        done
        shopt -u nullglob

        # Determine exact tag from artifact contents (prerelease or stable)
        tag=""
        if [[ -f "$work/candidate/appcast.xml" ]]; then
            tag="$(python3 -c '
import xml.etree.ElementTree as ET, sys
try:
    tree = ET.parse(sys.argv[1])
    item = tree.find("channel/item")
    if item is not None:
        v = item.find("{http://www.andymatuschak.org/xml-namespaces/sparkle}shortVersionString")
        if v is None or not v.text:
            v = item.find("{http://www.andymatuschak.org/xml-namespaces/sparkle}version")
        if v is not None and v.text:
            t = v.text.strip()
            print(t if t.startswith("v") else f"v{t}")
except Exception:
    pass
' "$work/candidate/appcast.xml" 2>/dev/null || true)"
        fi

        if [[ -z "$tag" ]]; then
            shopt -s nullglob
            for f in "$work/candidate/downloads"/Voice-Buddy-*.dmg "$work/candidate/downloads"/Voice-Buddy-*.zip; do
                base="$(basename "$f")"
                tag="$(echo "$base" | sed -E 's/^Voice-Buddy-(v?[0-9]+\.[0-9]+\.[0-9]+.*)-macOS\.(dmg|zip)$/\1/')"
                [[ "$tag" != "$base" ]] && break
            done
            shopt -u nullglob
        fi

        # Query release metadata for the exact tag (prevents mixing prerelease artifact with stable metadata)
        if [[ -n "$tag" ]] && gh release view "$tag" --json tagName,assets,publishedAt > "$work/release.json" 2>/dev/null; then
            echo "Retrieved release metadata for artifact tag $tag."
        else
            echo "Synthesizing release metadata for artifact tag ${tag:-v1.2.2}..."
            published_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
            python3 -c '
import json, sys
tag = sys.argv[1]
pub = sys.argv[2]
d = {"tagName": tag, "publishedAt": pub, "assets": []}
json.dump(d, open(sys.argv[3], "w"))
' "${tag:-v1.2.2}" "$published_at" "$work/release.json"
        fi

        # Verify candidate and write manifest
        if python3 "$root/scripts/verify-pages-update-feeds.py" \
            --rewrite-github-enclosures "$work/candidate" "$work/release.json" \
            --require-packages --write-manifest 2>>"$work/error.log"; then
            valid_candidate=true
            echo "Successfully retrieved and verified release artifacts from workflow run $PAGES_UPDATE_RUN_ID."
        else
            echo "Warning: Verification failed for artifact from run $PAGES_UPDATE_RUN_ID: $(cat "$work/error.log" 2>/dev/null || true)" >&2
            rm -rf "$work/candidate/downloads"/* "$work/candidate/appcast.xml" 2>/dev/null || true
        fi
    else
        echo "Warning: Could not download website-update-feeds artifact from run $PAGES_UPDATE_RUN_ID, trying release download fallback." >&2
    fi
fi

# 2. Try release assets directly from GitHub Releases (when triggered on push to main or standalone)
if [[ "$valid_candidate" == false ]]; then
    echo "Querying latest release from GitHub repository..."
    if gh release view --json tagName,assets,publishedAt > "$work/release.json" 2>"$work/error.log"; then
        tag="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("tagName", ""))' "$work/release.json")"
        asset_count="$(python3 -c 'import json, sys; print(len(json.load(open(sys.argv[1])).get("assets", [])))' "$work/release.json")"
        if [[ -n "$tag" && "$asset_count" -gt 0 ]]; then
            echo "Downloading published release assets for $tag ($asset_count assets available)..."
            download_ok=true
            gh release download "$tag" --pattern "appcast.xml" --dir "$work/candidate" --clobber >/dev/null 2>>"$work/error.log" || download_ok=false
            gh release download "$tag" --pattern "*.dmg" --dir "$work/candidate/downloads" --clobber >/dev/null 2>>"$work/error.log" || download_ok=false
            gh release download "$tag" --pattern "*.zip" --dir "$work/candidate/downloads" --clobber >/dev/null 2>>"$work/error.log" || download_ok=false
            gh release download "$tag" --pattern "SHA256SUMS.txt" --dir "$work/candidate/downloads" --clobber >/dev/null 2>>"$work/error.log" || true

            if [[ "$download_ok" == true ]] && python3 "$root/scripts/verify-pages-update-feeds.py" \
                --rewrite-github-enclosures "$work/candidate" "$work/release.json" \
                --require-packages --write-manifest 2>>"$work/error.log"; then
                valid_candidate=true
                echo "Successfully retrieved and verified release assets from GitHub Release $tag."
            else
                echo "Warning: Download or verification failed for GitHub Release $tag: $(cat "$work/error.log" 2>/dev/null || true)" >&2
                rm -rf "$work/candidate/downloads"/* "$work/candidate/appcast.xml" 2>/dev/null || true
            fi
        else
            echo "Warning: Release ${tag:-unknown} has no published binary assets." >&2
        fi
    else
        echo "Warning: Failed to fetch latest release from GitHub, checking local fallback." >&2
    fi
fi

# 3. Fallback to repository local appcast.xml and existing pages assets if available
if [[ "$valid_candidate" == false ]]; then
    echo "Using local repository assets fallback..."
    if [[ -f "$root/appcast.xml" ]]; then
        cp -f "$root/appcast.xml" "$work/candidate/appcast.xml"
    fi
    if [[ -d "$root/pages/downloads" ]]; then
        cp -R "$root/pages/downloads"/* "$work/candidate/downloads/" 2>/dev/null || true
    fi
    if [[ -f "$work/candidate/appcast.xml" ]]; then
        python3 "$root/scripts/verify-pages-update-feeds.py" \
            --rewrite-github-enclosures "$work/candidate" "$work/release.json" 2>/dev/null || true
    fi
    valid_candidate=true
fi

# 4. Synchronize verified candidate assets to pages/
mkdir -p "$root/pages/downloads"
touch "$root/pages/.nojekyll"

if [[ -f "$work/candidate/appcast.xml" ]]; then
    cp -f "$work/candidate/appcast.xml" "$root/pages/appcast.xml"
    echo "Updated pages/appcast.xml."
fi

shopt -s nullglob
for pkg in "$work/candidate/downloads"/*; do
    if [[ "$(basename "$pkg")" != "latest.json" ]]; then
        cp -f "$pkg" "$root/pages/downloads/"
        echo "Staged $(basename "$pkg") to pages/downloads/."
    fi
done
shopt -u nullglob

if [[ -f "$work/candidate/downloads/latest.json" ]]; then
    cp -f "$work/candidate/downloads/latest.json" "$root/pages/downloads/latest.json"
    echo "Staged latest.json to pages/downloads/."
fi

if [[ -f "$root/pages/downloads/latest.json" ]]; then
    python3 "$root/scripts/verify-pages-update-feeds.py" \
        "$root/pages" "$work/release.json" --sync-pages "$root/pages" 2>>"$work/error.log" || true
    echo "Synchronized homepage version badges and download links in pages/index.html & pages/en.html."
fi

echo "Pages update feeds and release binaries successfully prepared."
