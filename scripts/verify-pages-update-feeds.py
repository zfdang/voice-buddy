#!/usr/bin/env python3
"""Verify Sparkle appcast feeds and mirrored release binaries for Voice Buddy Pages."""
import argparse
import base64
import json
from pathlib import Path
import re
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
        if pkg_path.is_file():
            size = pkg_path.stat().st_size
            packages[key] = {
                'name': filename,
                'url': f'{PAGES_DOWNLOADS_BASE}/{filename}',
                'size': int(size),
            }

    # Ensure at least one primary package is staged before writing manifest
    if not any(k in packages for k in ('dmg', 'zip')):
        raise FileNotFoundError(
            f"Cannot write latest.json: neither DMG ({packages_dict.get('dmg')}) nor "
            f"ZIP ({packages_dict.get('zip')}) is present in {downloads_dir}"
        )

    checksum_path = downloads_dir / 'SHA256SUMS.txt'
    if checksum_path.is_file():
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
    """Migrate GitHub Release enclosure URLs in appcast.xml to the Pages downloads mirror.
    Only rewrite enclosures for packages that actually exist in the downloads directory."""
    directory = Path(directory)
    path = directory / 'appcast.xml'
    if not path.exists():
        return
    downloads_dir = directory / 'downloads'
    try:
        tree = ET.parse(path)
        modified = False
        for item in tree.findall('channel/item'):
            enclosure = item.find('enclosure')
            if enclosure is not None:
                url = enclosure.get('url', '')
                if 'github.com' in url and '/releases/download/' in url:
                    filename = url.rsplit('/', 1)[-1]
                    # Only rewrite if the package is actually present on disk in downloads/
                    if (downloads_dir / filename).is_file():
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
                elif require_packages:
                    raise ValueError('Sparkle edSignature missing from latest enclosure')
    elif require_packages:
        raise FileNotFoundError(f"Required appcast.xml not found in {directory}")

    if require_packages:
        if not downloads_dir.is_dir():
            raise FileNotFoundError(f"Downloads directory missing: {downloads_dir}")
        for key in ('dmg', 'zip'):
            filename = packages_dict.get(key)
            if not filename:
                raise FileNotFoundError(f"Missing expected filename for package {key}")
            file_path = downloads_dir / filename
            if not file_path.is_file():
                raise FileNotFoundError(f"Required release package missing: {filename} in {downloads_dir}")
            actual_size = file_path.stat().st_size
            if actual_size == 0:
                raise ValueError(f"Required release package is empty (0 bytes): {filename}")
            if actual_size > MAX_PAGES_FILE_BYTES:
                raise ValueError(f"{filename} exceeds max size limit ({actual_size} bytes)")
    elif downloads_dir.is_dir():
        for key, filename in packages_dict.items():
            file_path = downloads_dir / filename
            if file_path.is_file():
                actual_size = file_path.stat().st_size
                if actual_size > MAX_PAGES_FILE_BYTES:
                    raise ValueError(f'{filename} exceeds max size limit ({actual_size} bytes)')


def sync_homepage_versions(pages_dir: Path, manifest: dict):
    """Synchronize static version badges and release links in pages/index.html and pages/en.html."""
    tag = manifest.get('tag')
    if not tag:
        return
    packages = manifest.get('packages', {})
    dmg_url = (packages.get('dmg') or {}).get('url') or f'{PAGES_DOWNLOADS_BASE}/Voice-Buddy-{tag}-macOS.dmg'
    zip_url = (packages.get('zip') or {}).get('url') or f'{PAGES_DOWNLOADS_BASE}/Voice-Buddy-{tag}-macOS.zip'
    release_url = manifest.get('releasesUrl') or f'https://github.com/zfdang/voice-buddy/releases/tag/{tag}'

    for filename in ('index.html', 'en.html'):
        html_path = pages_dir / filename
        if not html_path.is_file():
            continue
        text = html_path.read_text(encoding='utf-8')
        text = re.sub(
            r'(<span\b[^>]*\bdata-vb-version\b[^>]*>)([^<]*)(</span>)',
            rf'\g<1>{tag}\g<3>',
            text,
        )
        text = re.sub(
            r'https://github\.com/zfdang/voice-buddy/releases/tag/v[0-9]+\.[0-9]+\.[0-9]+[^\s"\'<>]*',
            release_url,
            text,
        )
        text = re.sub(
            r'https://(?:github\.com/zfdang/voice-buddy/releases/download/[^/]+|myvoicebuddy\.com/downloads)/Voice-Buddy-[^"\'<>]+\.dmg',
            dmg_url,
            text,
        )
        text = re.sub(
            r'https://(?:github\.com/zfdang/voice-buddy/releases/download/[^/]+|myvoicebuddy\.com/downloads)/Voice-Buddy-[^"\'<>]+\.zip',
            zip_url,
            text,
        )
        html_path.write_text(text, encoding='utf-8')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=Path)
    parser.add_argument('release_json', type=Path)
    parser.add_argument('--require-packages', action='store_true')
    parser.add_argument('--write-manifest', action='store_true')
    parser.add_argument('--rewrite-github-enclosures', action='store_true')
    parser.add_argument('--sync-pages', type=Path, default=None, help='Path to pages/ to sync HTML versions')
    args = parser.parse_args()

    release = json.loads(args.release_json.read_text(encoding='utf-8'))
    if args.rewrite_github_enclosures:
        rewrite_github_release_enclosures(args.directory, release)
    # Always verify before writing manifest
    verify(args.directory, release, require_packages=args.require_packages)
    manifest_path = None
    if args.write_manifest:
        manifest_path = write_latest_manifest(args.directory, release)
    if args.sync_pages is not None:
        manifest_file = manifest_path or (args.directory / 'downloads' / 'latest.json')
        if manifest_file.is_file():
            manifest = json.loads(manifest_file.read_text(encoding='utf-8'))
            sync_homepage_versions(args.sync_pages, manifest)


if __name__ == '__main__':
    main()
