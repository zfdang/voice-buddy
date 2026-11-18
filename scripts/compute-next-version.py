#!/usr/bin/env python3
"""Compute next Semantic Version (SemVer) based on Conventional Commits since last release."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys


def get_base_version_and_ref(root_dir: Path):
    """Find the highest release version from git tags and appcast.xml, and the base git ref."""
    git_tags = []
    try:
        out = subprocess.check_output(
            ["git", "-C", str(root_dir), "tag", "-l"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
        for line in out.splitlines():
            line = line.strip()
            m = re.match(r"^v?(\d+)\.(\d+)\.(\d+)$", line)
            if m:
                v_tuple = tuple(map(int, m.groups()))
                git_tags.append((v_tuple, line))
    except Exception:
        pass
    git_tags.sort()

    appcast_versions = []
    appcast_path = root_dir / "appcast.xml"
    if appcast_path.is_file():
        try:
            import xml.etree.ElementTree as ET
            tree = ET.parse(appcast_path)
            for item in tree.findall("channel/item"):
                v = item.find("{http://www.andymatuschak.org/xml-namespaces/sparkle}shortVersionString")
                if v is None or not v.text:
                    v = item.find("{http://www.andymatuschak.org/xml-namespaces/sparkle}version")
                if v is not None and v.text:
                    m = re.match(r"^v?(\d+)\.(\d+)\.(\d+)$", v.text.strip())
                    if m:
                        appcast_versions.append(tuple(map(int, m.groups())))
        except Exception:
            pass
    appcast_versions.sort()

    all_versions = [vt for vt, _ in git_tags] + appcast_versions
    base_version = max(all_versions) if all_versions else (0, 1, 0)
    base_ref = git_tags[-1][1] if git_tags else None

    return base_version, base_ref


def analyze_commits(root_dir: Path, base_ref: str | None):
    """Analyze Conventional Commits since base_ref to determine major/minor/patch bump."""
    if base_ref:
        log_range = f"{base_ref}..HEAD"
    else:
        log_range = "HEAD"

    cmd = ["git", "-C", str(root_dir), "log", log_range, "--format=%B%x1f"]
    try:
        out = subprocess.check_output(cmd, text=True, errors="replace", stderr=subprocess.DEVNULL)
    except Exception:
        out = ""

    commits = [c.strip() for c in out.split("\x1f") if c.strip()]

    bump = "patch"
    major_reasons = []
    minor_reasons = []
    patch_reasons = []

    for commit_msg in commits:
        lines = commit_msg.splitlines()
        first_line = lines[0].strip() if lines else ""
        body = "\n".join(lines[1:]) if len(lines) > 1 else ""

        # Breaking change: "feat!:", "fix!:", or "BREAKING CHANGE:" in footer
        if (
            re.match(r"^[a-zA-Z]+(\([^\)]+\))?!:", first_line)
            or "BREAKING CHANGE:" in body
            or "BREAKING-CHANGE:" in body
        ):
            bump = "major"
            major_reasons.append(first_line)
        # New feature: "feat:" or "feat(...):"
        elif re.match(r"^feat(\([^\)]+\))?:", first_line):
            if bump != "major":
                bump = "minor"
            minor_reasons.append(first_line)
        # Bug fix, perf improvement, refactor: "fix:", "perf:", "refactor:"
        elif re.match(r"^(fix|perf|refactor)(\([^\)]+\))?:", first_line):
            patch_reasons.append(first_line)

    reasons = major_reasons if bump == "major" else (minor_reasons if bump == "minor" else patch_reasons)
    return bump, reasons, commits


def compute_next_version(base_version: tuple[int, int, int], bump: str) -> tuple[int, int, int]:
    major, minor, patch = base_version
    if bump == "major":
        return (major + 1, 0, 0)
    elif bump == "minor":
        return (major, minor + 1, 0)
    else:
        return (major, minor, patch + 1)


def main():
    parser = argparse.ArgumentParser(description="Calculate next Semantic Version based on Conventional Commits")
    parser.add_argument("--repo-dir", type=Path, default=Path(__file__).resolve().parent.parent, help="Repository root path")
    parser.add_argument("--verbose", action="store_true", help="Print detailed bump analysis")
    parser.add_argument("--format", choices=["tag", "version", "env"], default="tag", help="Output format")
    args = parser.parse_args()

    base_version, base_ref = get_base_version_and_ref(args.repo_dir)
    bump, reasons, all_commits = analyze_commits(args.repo_dir, base_ref)
    next_version = compute_next_version(base_version, bump)

    tag = f"v{next_version[0]}.{next_version[1]}.{next_version[2]}"
    version_str = f"{next_version[0]}.{next_version[1]}.{next_version[2]}"

    if args.verbose:
        base_str = f"{base_version[0]}.{base_version[1]}.{base_version[2]}"
        sys.stderr.write(f"Base version : v{base_str} (reference: {base_ref or 'initial commit'})\n")
        sys.stderr.write(f"Scanned      : {len(all_commits)} commits\n")
        sys.stderr.write(f"Bump type    : {bump.upper()}\n")
        if reasons:
            sys.stderr.write(f"Primary triggers ({len(reasons)}):\n")
            for r in reasons[:5]:
                sys.stderr.write(f"  - {r}\n")
        sys.stderr.write(f"Calculated   : {tag}\n")

    if args.format == "tag":
        print(tag)
    elif args.format == "version":
        print(version_str)
    elif args.format == "env":
        print(f"RELEASE_TAG={tag}")
        print(f"RELEASE_VERSION={version_str}")
        print(f"RELEASE_BUMP={bump}")


if __name__ == "__main__":
    main()
