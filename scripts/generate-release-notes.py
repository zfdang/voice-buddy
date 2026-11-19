#!/usr/bin/env python3
"""Generate concise, changelog-focused GitHub release notes for Voice Buddy."""
from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import shutil
import subprocess


SEMVER_RE = re.compile(
    r"^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$"
)
CONVENTIONAL_RE = re.compile(
    r"^(?P<kind>[A-Za-z]+)(?:\((?P<scope>[^)]+)\))?(?P<breaking>!)?:\s*(?P<desc>.+)$"
)
GH_BULLET_RE = re.compile(
    r"^\s*[-*]\s+(?P<title>.+?)(?:\s+by\s+@[A-Za-z0-9_-]+(?:\[bot\])?(?:\s+in\s+(?P<url>https://github\.com/[^/\s]+/[^/\s]+/pull/(?P<pr>\d+)))?)?\s*$"
)
PR_FIXUP_RE = re.compile(r"^[A-Za-z]+\(pr\d+\):", re.IGNORECASE)
RELEASE_COMMIT_RE = re.compile(r"^chore\(release\):", re.IGNORECASE)
CODE_SPAN_SPLIT_RE = re.compile(r"(`[^`]*`)")

CATEGORY_ORDER = (
    "Breaking Changes",
    "Features",
    "Bug Fixes",
    "Improvements & Refactoring",
    "Other Changes",
)

KIND_TO_CATEGORY = {
    "feat": "Features",
    "fix": "Bug Fixes",
    "perf": "Improvements & Refactoring",
    "refactor": "Improvements & Refactoring",
}


@dataclass(frozen=True)
class ChangelogEntry:
    category: str
    scope: str | None
    description: str
    ref_suffix: str = ""


def parse_semver(tag: str) -> tuple[int, int, int, int, tuple[tuple[int, int | str], ...]] | None:
    """Return a sortable SemVer key, placing stable releases ahead of prereleases."""
    match = SEMVER_RE.match(tag.strip())
    if not match:
        return None
    major, minor, patch = int(match.group(1)), int(match.group(2)), int(match.group(3))
    pre = match.group(4)
    if not pre:
        return (major, minor, patch, 1, ())
    parts: list[tuple[int, int | str]] = []
    for token in pre.split("."):
        if token.isdigit():
            parts.append((0, int(token)))
        else:
            parts.append((1, token))
    return (major, minor, patch, 0, tuple(parts))


def is_prerelease_tag(tag: str) -> bool:
    parsed = parse_semver(tag)
    return parsed is not None and parsed[3] == 0


def _run_git(repo_dir: Path, args: list[str]) -> str:
    return subprocess.check_output(
        ["git", "-C", str(repo_dir), *args],
        text=True,
        errors="replace",
        stderr=subprocess.DEVNULL,
    )


def resolve_previous_tag(repo_dir: Path, current_tag: str, commit: str | None = None) -> str | None:
    """Find the most recent SemVer tag preceding current_tag reachable from commit."""
    try:
        args = ["tag", "-l"]
        if commit:
            args.extend(["--merged", commit])
        raw_tags = _run_git(repo_dir, args).splitlines()
        if commit and not raw_tags:
            raw_tags = _run_git(repo_dir, ["tag", "-l"]).splitlines()
    except Exception:
        return None

    current_semver = parse_semver(current_tag)
    allow_prerelease = is_prerelease_tag(current_tag)

    candidates: list[tuple[tuple[int, int, int, int, tuple[tuple[int, int | str], ...]], str]] = []
    for raw in raw_tags:
        tag = raw.strip()
        if not tag or tag == current_tag:
            continue
        parsed = parse_semver(tag)
        if parsed is None:
            continue
        if current_semver is not None and parsed >= current_semver:
            continue
        candidates.append((parsed, tag))

    if not candidates:
        return None

    if not allow_prerelease:
        stable = [c for c in candidates if c[0][3] == 1]
        if stable:
            candidates = stable

    candidates.sort(key=lambda item: item[0], reverse=True)
    return candidates[0][1]


def _is_noise_subject(subject: str) -> bool:
    s = subject.strip()
    if not s:
        return True
    if "[skip ci]" in s.lower():
        return True
    if RELEASE_COMMIT_RE.match(s):
        return True
    if PR_FIXUP_RE.match(s):
        return True
    return False


def _capitalize_first(text: str) -> str:
    if text and text[0].islower():
        return text[0].upper() + text[1:]
    return text


def _escape_markdown(text: str) -> str:
    """Escape HTML angle brackets and markdown link brackets outside inline code spans."""
    parts = CODE_SPAN_SPLIT_RE.split(text)
    for idx in range(0, len(parts), 2):
        segment = parts[idx]
        segment = (
            segment.replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("[", "\\[")
            .replace("]", "\\]")
        )
        parts[idx] = segment
    return "".join(parts)


def classify_subject(subject: str, ref_suffix: str = "") -> ChangelogEntry:
    match = CONVENTIONAL_RE.match(subject.strip())
    if not match:
        return ChangelogEntry(
            category="Other Changes",
            scope=None,
            description=_escape_markdown(_capitalize_first(subject.strip())),
            ref_suffix=ref_suffix,
        )

    kind = match.group("kind").lower()
    raw_scope = match.group("scope").strip() if match.group("scope") else None
    scope = _escape_markdown(raw_scope) if raw_scope else None
    breaking = bool(match.group("breaking"))
    desc = _escape_markdown(_capitalize_first(match.group("desc").strip()))

    category = "Breaking Changes" if breaking else KIND_TO_CATEGORY.get(kind, "Other Changes")
    return ChangelogEntry(category=category, scope=scope, description=desc, ref_suffix=ref_suffix)


def parse_github_notes_with_stats(raw_body: str) -> tuple[list[ChangelogEntry], int]:
    """Extract clean PR changelog entries and count filtered noise entries."""
    entries: list[ChangelogEntry] = []
    filtered_count = 0
    in_contributors = False

    for line in raw_body.splitlines():
        stripped = line.strip()
        if stripped.startswith("## "):
            in_contributors = "new contributors" in stripped.lower()
            continue
        if in_contributors or stripped.startswith("**Full Changelog**:"):
            continue
        match = GH_BULLET_RE.match(line)
        if not match:
            continue
        title = match.group("title").strip()
        if _is_noise_subject(title):
            filtered_count += 1
            continue
        pr_num = match.group("pr")
        ref_suffix = f" (#{pr_num})" if pr_num else ""
        entries.append(classify_subject(title, ref_suffix=ref_suffix))

    return entries, filtered_count


def parse_github_notes(raw_body: str) -> list[ChangelogEntry]:
    """Extract clean PR changelog entries from GitHub generate-notes output."""
    entries, _ = parse_github_notes_with_stats(raw_body)
    return entries


def fetch_github_generated_notes(
    repository: str,
    tag: str,
    commit: str | None,
    previous_tag: str | None,
) -> tuple[list[ChangelogEntry], int, bool]:
    """Query GitHub's release note generator for PR-level titles when gh is available."""
    if not shutil.which("gh"):
        return [], 0, False

    cmd = [
        "gh",
        "api",
        f"repos/{repository}/releases/generate-notes",
        "-f",
        f"tag_name={tag}",
        "--jq",
        ".body",
    ]
    if commit:
        cmd.extend(["-f", f"target_commitish={commit}"])
    if previous_tag:
        cmd.extend(["-f", f"previous_tag_name={previous_tag}"])

    try:
        body = subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL, timeout=15)
    except Exception:
        return [], 0, False
    entries, filtered_count = parse_github_notes_with_stats(body)
    return entries, filtered_count, True


def fetch_git_log_entries(
    repo_dir: Path,
    commit: str | None,
    previous_tag: str | None,
) -> tuple[list[ChangelogEntry], int]:
    """Build changelog entries directly from git commits when GitHub API is unavailable."""
    target = commit or "HEAD"
    log_range = f"{previous_tag}..{target}" if previous_tag else target
    try:
        out = _run_git(repo_dir, ["log", "--no-merges", "--format=%H%x1f%s%x1e", log_range])
    except Exception:
        return [], 0

    entries: list[ChangelogEntry] = []
    filtered_count = 0
    for record in out.split("\x1e"):
        record = record.strip()
        if not record or "\x1f" not in record:
            continue
        sha, subject = record.split("\x1f", 1)
        subject = subject.strip()
        if _is_noise_subject(subject):
            filtered_count += 1
            continue
        entries.append(classify_subject(subject, ref_suffix=f" (`{sha[:7]}`)"))

    return entries, filtered_count


def format_changelog_sections(entries: list[ChangelogEntry], filtered_count: int = 0) -> list[str]:
    """Group and format changelog entries into concise markdown sections."""
    lines = ["## What's Changed", ""]
    if not entries:
        if filtered_count > 0:
            noun = "commit" if filtered_count == 1 else "commits"
            lines.append(
                f"- Maintenance and build updates ({filtered_count} automated/housekeeping {noun} omitted)."
            )
        else:
            lines.append("- Maintenance and build updates.")
        lines.append("")
        return lines

    grouped: dict[str, list[ChangelogEntry]] = {cat: [] for cat in CATEGORY_ORDER}
    for entry in entries:
        grouped.setdefault(entry.category, []).append(entry)

    for category in CATEGORY_ORDER:
        bucket = grouped.get(category)
        if not bucket:
            continue
        lines.append(f"### {category}")
        for entry in bucket:
            prefix = f"**{entry.scope}**: " if entry.scope else ""
            lines.append(f"- {prefix}{entry.description}{entry.ref_suffix}")
        lines.append("")

    return lines


def generate_notes(
    tag: str,
    commit: str,
    dmg_file: Path,
    checksums_file: Path,
    repository: str,
    repo_dir: Path | None = None,
    previous_tag: str | None = None,
    use_github_api: bool = True,
) -> str:
    root_dir = repo_dir or Path(__file__).resolve().parent.parent
    prev_tag = previous_tag if previous_tag is not None else resolve_previous_tag(root_dir, tag, commit or None)

    entries: list[ChangelogEntry] = []
    filtered_count = 0
    api_ok = False
    if use_github_api:
        entries, filtered_count, api_ok = fetch_github_generated_notes(repository, tag, commit or None, prev_tag)
    if not entries and not (api_ok and filtered_count > 0):
        entries, git_filtered_count = fetch_git_log_entries(root_dir, commit or None, prev_tag)
        filtered_count = max(filtered_count, git_filtered_count)

    notes = format_changelog_sections(entries, filtered_count=filtered_count)

    dmg_name = dmg_file.name
    checksums = checksums_file.read_text(encoding="utf-8").strip() if checksums_file.exists() else ""
    short_sha = commit[:7] if commit else ""

    meta_parts = [
        f"**Download**: [{dmg_name}](https://myvoicebuddy.com/downloads/{dmg_name})",
        "macOS 15.0+ (Apple Silicon)",
    ]
    if prev_tag:
        meta_parts.append(
            f"[Full Changelog](https://github.com/{repository}/compare/{prev_tag}...{tag})"
        )

    notes.extend([
        "---",
        "",
        " · ".join(meta_parts),
        "",
    ])

    if short_sha or checksums:
        notes.extend([
            "<details>",
            "<summary>Checksums & Build Info</summary>",
            "",
        ])
        if short_sha:
            notes.append(f"- **Commit**: `{short_sha}`")
        if checksums:
            notes.extend([
                "- **SHA256**:",
                "",
                "```text",
                checksums,
                "```",
            ])
        notes.extend([
            "",
            "</details>",
            "",
        ])

    return "\n".join(notes)


def main():
    parser = argparse.ArgumentParser(description="Generate Voice Buddy release notes")
    parser.add_argument("--tag", required=True, help="Release tag (e.g. v1.2.2)")
    parser.add_argument("--commit", required=True, help="Release git commit SHA")
    parser.add_argument("--dmg-file", type=Path, required=True, help="Path to DMG release file")
    parser.add_argument("--checksums-file", type=Path, required=True, help="Path to SHA256SUMS.txt")
    parser.add_argument("--repository", default="zfdang/voice-buddy", help="GitHub repository (owner/repo)")
    parser.add_argument("--repo-dir", type=Path, default=None, help="Git repository root path")
    parser.add_argument("--previous-tag", default=None, help="Override previous release tag")
    parser.add_argument("--no-github-api", action="store_true", help="Skip GitHub generate-notes API and use local git log")
    parser.add_argument("--output", type=Path, required=True, help="Output markdown file path")

    args = parser.parse_args()

    content = generate_notes(
        tag=args.tag,
        commit=args.commit,
        dmg_file=args.dmg_file,
        checksums_file=args.checksums_file,
        repository=args.repository,
        repo_dir=args.repo_dir,
        previous_tag=args.previous_tag,
        use_github_api=not args.no_github_api,
    )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(content, encoding="utf-8")
    print(f"Generated release notes at {args.output}")


if __name__ == "__main__":
    main()
