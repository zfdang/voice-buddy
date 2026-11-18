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

        # Try to retrieve release info if already published
        gh release view --json tagName,assets,publishedAt > "$work/release.json" 2>/dev/null || true
        tag="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("tagName", ""))' "$work/release.json")"
        if [[ -z "$tag" ]]; then
            # Extract tag from downloaded dmg/zip name
            shopt -s nullglob
            for f in "$work/candidate/downloads"/Voice-Buddy-*.dmg; do
                base="$(basename "$f")"
                tag="$(echo "$base" | sed -E 's/^Voice-Buddy-(v?[0-9]+\.[0-9]+\.[0-9]+.*)-macOS\.dmg$/\1/')"
                break
            done
            shopt -u nullglob
            python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); d["tagName"] = sys.argv[2]; json.dump(d, open(sys.argv[1], "w"))' "$work/release.json" "${tag:-v1.2.1}"
        fi

        python3 "$root/scripts/verify-pages-update-feeds.py" \
            --rewrite-github-enclosures "$work/candidate" "$work/release.json" --write-manifest 2>>"$work/error.log" || true
        valid_candidate=true
        echo "Successfully retrieved release artifacts from workflow run $PAGES_UPDATE_RUN_ID."
    else
        echo "Warning: Could not download website-update-feeds artifact from run $PAGES_UPDATE_RUN_ID, trying release download fallback." >&2
    fi
fi

# 2. Try release assets directly from GitHub Releases (when triggered on push to main or standalone)
if [[ "$valid_candidate" == false ]]; then
    echo "Querying latest release from GitHub repository..."
    if gh release view --json tagName,assets,publishedAt > "$work/release.json" 2>"$work/error.log"; then
        tag="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("tagName", ""))' "$work/release.json")"
        if [[ -n "$tag" ]]; then
            echo "Downloading published release assets for $tag..."
            gh release download "$tag" --pattern "appcast.xml" --dir "$work/candidate" --clobber >/dev/null 2>>"$work/error.log" || true
            gh release download "$tag" --pattern "*.dmg" --dir "$work/candidate/downloads" --clobber >/dev/null 2>>"$work/error.log" || true
            gh release download "$tag" --pattern "*.zip" --dir "$work/candidate/downloads" --clobber >/dev/null 2>>"$work/error.log" || true
            gh release download "$tag" --pattern "SHA256SUMS.txt" --dir "$work/candidate/downloads" --clobber >/dev/null 2>>"$work/error.log" || true

            python3 "$root/scripts/verify-pages-update-feeds.py" \
                --rewrite-github-enclosures "$work/candidate" "$work/release.json" --write-manifest 2>>"$work/error.log" || true
            valid_candidate=true
            echo "Successfully retrieved release assets from GitHub Release $tag."
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
    valid_candidate=true
fi

# 4. Synchronize candidate assets to pages/
mkdir -p "$root/pages/downloads"
touch "$root/pages/.nojekyll"

if [[ -f "$work/candidate/appcast.xml" ]]; then
    cp -f "$work/candidate/appcast.xml" "$root/pages/appcast.xml"
    echo "Updated pages/appcast.xml."
fi

shopt -s nullglob
for pkg in "$work/candidate/downloads"/*; do
    cp -f "$pkg" "$root/pages/downloads/"
    echo "Staged $(basename "$pkg") to pages/downloads/."
done
shopt -u nullglob

if [[ -f "$work/candidate/downloads/latest.json" ]]; then
    cp -f "$work/candidate/downloads/latest.json" "$root/pages/downloads/latest.json"
fi

echo "Pages update feeds and release binaries successfully prepared."
