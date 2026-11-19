#!/usr/bin/env python3
"""Unit tests for scripts/generate-release-notes.py."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


def load_module():
    script_path = Path(__file__).resolve().parent / "generate-release-notes.py"
    spec = importlib.util.spec_from_file_location("generate_release_notes", script_path)
    module = importlib.util.module_from_spec(spec)
    sys.modules["generate_release_notes"] = module
    spec.loader.exec_module(module)
    return module


grn = load_module()


class ReleaseNotesTests(unittest.TestCase):
    def test_parse_github_notes_strips_author_noise_and_categorizes(self):
        raw = """## What's Changed
* feat(ui): group sidebar navigation tabs into three sections by @zfdang in https://github.com/zfdang/voice-buddy/pull/62
* fix(engines): harden SenseVoice strides and AppleSpeech timeout by @zfdang in https://github.com/zfdang/voice-buddy/pull/64
* refactor(app): decompose App.swift into focused stores by @zfdang in https://github.com/zfdang/voice-buddy/pull/65
* chore(release): update appcast.xml for v1.6.0 [skip ci] by @github-actions in https://github.com/zfdang/voice-buddy/pull/99
* docs: update README by @contributor in https://github.com/zfdang/voice-buddy/pull/66

## New Contributors
* @contributor made their first contribution in https://github.com/zfdang/voice-buddy/pull/66

**Full Changelog**: https://github.com/zfdang/voice-buddy/compare/v1.5.1...v1.6.0
"""
        entries = grn.parse_github_notes(raw)
        self.assertEqual(
            [(e.category, e.scope, e.description, e.ref_suffix) for e in entries],
            [
                ("Features", "ui", "Group sidebar navigation tabs into three sections", " (#62)"),
                ("Bug Fixes", "engines", "Harden SenseVoice strides and AppleSpeech timeout", " (#64)"),
                ("Improvements & Refactoring", "app", "Decompose App.swift into focused stores", " (#65)"),
                ("Other Changes", None, "Update README", " (#66)"),
            ],
        )

    def test_git_log_fallback_filters_release_and_pr_fixup_commits(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            subprocess.run(["git", "init"], cwd=repo, check=True, stdout=subprocess.DEVNULL)
            subprocess.run(["git", "config", "user.name", "Tester"], cwd=repo, check=True)
            subprocess.run(["git", "config", "user.email", "tester@example.com"], cwd=repo, check=True)

            (repo / "file.txt").write_text("v1\n", encoding="utf-8")
            subprocess.run(["git", "add", "file.txt"], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-m", "feat(core): initial"], cwd=repo, check=True, stdout=subprocess.DEVNULL)
            subprocess.run(["git", "tag", "v1.0.0"], cwd=repo, check=True)

            for msg in [
                "chore(release): update appcast.xml for v1.0.0 [skip ci]",
                "feat(vad): add Silero adaptive threshold",
                "fix(pr64): tweak review comment wording",
                "fix(asr): handle empty buffer",
            ]:
                (repo / "file.txt").write_text(msg + "\n", encoding="utf-8")
                subprocess.run(["git", "add", "file.txt"], cwd=repo, check=True)
                subprocess.run(["git", "commit", "-m", msg], cwd=repo, check=True, stdout=subprocess.DEVNULL)

            sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
            checksums = repo / "SHA256SUMS.txt"
            checksums.write_text("deadbeef  Voice-Buddy-v1.1.0-macOS.dmg\n", encoding="utf-8")

            notes = grn.generate_notes(
                tag="v1.1.0",
                commit=sha,
                dmg_file=repo / "Voice-Buddy-v1.1.0-macOS.dmg",
                checksums_file=checksums,
                repository="zfdang/voice-buddy",
                repo_dir=repo,
                use_github_api=False,
            )

            self.assertIn("### Features", notes)
            self.assertIn("- **vad**: Add Silero adaptive threshold", notes)
            self.assertIn("### Bug Fixes", notes)
            self.assertIn("- **asr**: Handle empty buffer", notes)
            self.assertNotIn("appcast.xml", notes)
            self.assertNotIn("fix(pr64)", notes)
            self.assertIn("[Full Changelog](https://github.com/zfdang/voice-buddy/compare/v1.0.0...v1.1.0)", notes)
            self.assertIn("<details>", notes)
            self.assertIn("deadbeef  Voice-Buddy-v1.1.0-macOS.dmg", notes)
            self.assertNotIn("raw.githubusercontent.com", notes)

    def test_resolve_previous_tag_skips_prereleases_for_stable_release(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            subprocess.run(["git", "init"], cwd=repo, check=True, stdout=subprocess.DEVNULL)
            subprocess.run(["git", "config", "user.name", "Tester"], cwd=repo, check=True)
            subprocess.run(["git", "config", "user.email", "tester@example.com"], cwd=repo, check=True)

            for i, tag in enumerate(["v1.5.0", "v1.6.0-rc.1", "v1.6.0"]):
                (repo / "file.txt").write_text(f"{i}\n", encoding="utf-8")
                subprocess.run(["git", "add", "file.txt"], cwd=repo, check=True)
                subprocess.run(["git", "commit", "-m", f"chore: {tag}"], cwd=repo, check=True, stdout=subprocess.DEVNULL)
                subprocess.run(["git", "tag", tag], cwd=repo, check=True)

            sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
            self.assertEqual(grn.resolve_previous_tag(repo, "v1.6.0", sha), "v1.5.0")
            self.assertEqual(grn.resolve_previous_tag(repo, "v1.6.1-rc.1", sha), "v1.6.0")


if __name__ == "__main__":
    unittest.main()
