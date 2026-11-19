# Contributing to Voice Buddy

Thank you for your interest in contributing to Voice Buddy!

## Development Requirements

- macOS 15.0 (Sequoia) or later on Apple Silicon (`arm64`)
- Xcode 26+ (Swift 6.2+ toolchain with Metal support)

## Workflow & Branching Rules

1. **Never push directly to `main`.** Always create a feature/fix branch from `main` (e.g. `feat/...`, `fix/...`, `docs/...`, `chore/...`) and open a Pull Request.
2. Follow [Conventional Commits](https://www.conventionalcommits.org/) for commit messages (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`), as release versioning relies on commit history.
3. Run the test suite locally before opening or updating a PR:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

4. To build and sign the `.app` bundle locally:

```bash
./build.sh
```

By default, `scripts/build.sh` automatically selects `"Voice Buddy Local Development"` if present in your keychain and otherwise falls back to ad-hoc signing (`-`). If you want to sign with a `Developer ID Application` or other specific keychain certificate, pass `-s` or set `VOICE_BUDDY_SIGN_IDENTITY`:

```bash
./build.sh -s "Developer ID Application: Your Name (TEAMID)"
# or:
VOICE_BUDDY_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh
```

For repository governance and release workflow details, see [docs/repository-governance.md](docs/repository-governance.md) and [AGENTS.md](AGENTS.md).
