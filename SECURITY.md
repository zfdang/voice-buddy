# Security Policy

## Supported Versions

Security fixes are released on the latest tagged release and published through [GitHub Releases](https://github.com/zfdang/voice-buddy/releases) and the official Sparkle update feed (`https://myvoicebuddy.com/appcast.xml`).

## Privacy & Local-First Design

Voice Buddy processes microphone audio, speech recognition, and LLM text refinement entirely on-device on Apple Silicon Macs:

- Audio buffers are kept in memory for local model inference (Whisper / SenseVoice / Qwen3-ASR) and never uploaded to cloud APIs. When using the built-in Apple Speech engine, a temporary WAV file is briefly written to the system temp directory and deleted immediately after recognition completes.
- Secure input fields (`IsSecureEventInputEnabled()`, `AXSecureTextField`, `AXProtectedContent`, and sensitive field identifiers) are blocked from automatic insertion.
- Clipboard writes used for pasting are tagged with `org.nspasteboard.ConcealedType` and `org.nspasteboard.TransientType` and restored when untouched.

## Reporting a Vulnerability

If you discover a security vulnerability, please **do not** open a public GitHub issue with exploit details. Instead:

1. Report it privately via [GitHub Security Advisories](https://github.com/zfdang/voice-buddy/security/advisories/new) (preferred), or contact the maintainer through the repository profile.
2. Include a description of the issue, affected version/commit, reproduction steps, and potential impact.

We will acknowledge receipt promptly and coordinate a fix before public disclosure.
