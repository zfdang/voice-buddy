#!/usr/bin/env python3
"""Generate structured release notes for Voice Buddy releases."""
import argparse
import os
from pathlib import Path


def generate_notes(tag: str, commit: str, dmg_file: Path, checksums_file: Path, repository: str) -> str:
    dmg_name = dmg_file.name
    checksums = ""
    if checksums_file.exists():
        checksums = checksums_file.read_text(encoding="utf-8").strip()

    notes = [
        f"## Voice Buddy {tag}",
        "",
        f"- **Commit**: `{commit}`",
        "- **Architecture**: Apple Silicon (arm64, M-Series M1+) / macOS 15.0+",
        "- **Offline-first voice typing with local Qwen3-ASR and Qwen LLM**",
        "",
        "### Sparkle Update Feed & Mirrors",
        "- Direct Domain Update Feed: `https://myvoicebuddy.com/appcast.xml`",
        f"- Direct Binary Download: `https://myvoicebuddy.com/downloads/{dmg_name}`",
        f"- GitHub Raw Mirror: `https://raw.githubusercontent.com/{repository}/main/appcast.xml`",
        "",
    ]

    if checksums:
        notes.extend([
            "### SHA256 Checksums",
            "```",
            checksums,
            "```",
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
    parser.add_argument("--output", type=Path, required=True, help="Output markdown file path")

    args = parser.parse_args()

    content = generate_notes(
        tag=args.tag,
        commit=args.commit,
        dmg_file=args.dmg_file,
        checksums_file=args.checksums_file,
        repository=args.repository,
    )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(content, encoding="utf-8")
    print(f"Generated release notes at {args.output}")


if __name__ == "__main__":
    main()
