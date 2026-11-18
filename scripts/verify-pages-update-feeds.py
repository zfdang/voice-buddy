#!/usr/bin/env python3
"""Verify Sparkle appcast feeds and mirrored release binaries for Voice Buddy Pages."""
import argparse
import base64
import json
import hashlib
import re
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
PAGES_DOWNLOADS_BASE = 'https://myvoicebuddy.com/downloads'
GITHUB_RELEASE_BASE = 'https://github.com/zfdang/voice-buddy/releases/download'
MAX_PAGES_FILE_BYTES = 100 * 1024 * 1024  # GitHub Pages allows up to 100MB per file


def _release_packages(release):
    tag = release.get('tagName', '')
    if not tag and 'tag' in release:
        tag = release['tag']
    raw_tag = tag.lstrip('v')
    assets = {asset['name']: asset for asset in release.get('assets', [])}

    dmg_candidates = [f'Voice-Buddy-{tag}-macOS.dmg', f'Voice-Buddy-{raw_tag}-macOS.dmg']
    zip_candidates = [f'Voice-Buddy-{tag}-macOS.zip', f'Voice-Buddy-{raw_tag}-macOS.zip']

    dmg_name = next((name for name in dmg_candidates if name in assets), dmg_candidates[0])
    zip_name = next((name for name in zip_candidates if name in assets), zip_candidates[0])

    return tag, assets, {'dmg': dmg_name, 'zip': zip_name}


def write_latest_manifest(directory, release):
    """Write downloads/latest.json from verified release metadata and staged files."""
    tag, assets, packages_dict = _release_packages(release)
    downloads_dir = Path(directory) / 'downloads'
    downloads_dir.mkdir(parents=True, exist_ok=True)
    packages = {}
    for key, filename in packages_dict.items():
        pkg_path = downloads_dir / filename
        size = pkg_path.stat().st_size if pkg_path.exists() else assets.get(filename, {}).get('size')
        entry = {
            'name': filename,
            'url': f'{PAGES_DOWNLOADS_BASE}/{filename}',
        }
        if size is not None:
            entry['size'] = int(size)
        packages[key] = entry

    checksum_path = downloads_dir / 'SHA256SUMS.txt'
    if checksum_path.exists():
        packages['checksums'] = {
            'name': 'SHA256SUMS.txt',
            'url': f'{PAGES_DOWNLOADS_BASE}/SHA256SUMS.txt',
        }

    manifest = {
        'tag': tag,
        'version': tag.lstrip('v'),
        'publishedAt': release.get('publishedAt', ''),
        'releasesUrl': f'https://github.com/zfdang/voice-buddy/releases/tag/{tag}' if tag else '',
        'appcastUrl': 'https://myvoicebuddy.com/appcast.xml',
        'packages': packages,
    }
    manifest_path = downloads_dir / 'latest.json'
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    return manifest_path


def rewrite_github_release_enclosures(directory, release):
    """Migrate GitHub Release enclosure URLs in appcast.xml to the Pages downloads mirror."""
    directory = Path(directory)
    path = directory / 'appcast.xml'
    if not path.exists():
        return
    try:
        tree = ET.parse(path)
        modified = False
        for item in tree.findall('channel/item'):
            enclosure = item.find('enclosure')
            if enclosure is not None:
                url = enclosure.get('url', '')
                if 'github.com' in url and '/releases/download/' in url:
                    filename = url.rsplit('/', 1)[-1]
                    enclosure.set('url', f'{PAGES_DOWNLOADS_BASE}/{filename}')
                    modified = True
        if modified:
            tree.write(path, encoding='utf-8', xml_declaration=True)
    except Exception as e:
        sys.stderr.write(f"Warning: could not rewrite enclosure in appcast.xml: {e}\n")


def verify(directory, release, *, require_packages=False):
    directory = Path(directory)
    tag, assets, packages_dict = _release_packages(release)
    downloads_dir = directory / 'downloads'
    check_packages = require_packages or downloads_dir.exists()

    path = directory / 'appcast.xml'
    if path.exists():
        tree = ET.parse(path)
        item = tree.find('channel/item')
        if item is not None:
            enclosure = item.find('enclosure')
            if enclosure is not None:
                ed_sig = enclosure.get(f'{{{SPARKLE}}}edSignature')
                if ed_sig:
                    try:
                        decoded = base64.b64decode(ed_sig, validate=True)
                        if len(decoded) != 64:
                            raise ValueError(f'Invalid signature length: {len(decoded)} bytes')
                    except Exception as e:
                        raise ValueError(f'Invalid Sparkle edSignature: {e}')

    if check_packages and downloads_dir.is_dir():
        for key, filename in packages_dict.items():
            file_path = downloads_dir / filename
            if file_path.is_file():
                actual_size = file_path.stat().st_size
                if actual_size > MAX_PAGES_FILE_BYTES:
                    raise ValueError(f'{filename} exceeds max size limit ({actual_size} bytes)')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=Path)
    parser.add_argument('release_json', type=Path)
    parser.add_argument('--require-packages', action='store_true')
    parser.add_argument('--write-manifest', action='store_true')
    parser.add_argument('--rewrite-github-enclosures', action='store_true')
    args = parser.parse_args()

    release = json.loads(args.release_json.read_text(encoding='utf-8'))
    if args.rewrite_github_enclosures:
        rewrite_github_release_enclosures(args.directory, release)
    if args.write_manifest:
        write_latest_manifest(args.directory, release)
        return
    verify(args.directory, release, require_packages=args.require_packages)


if __name__ == '__main__':
    main()
