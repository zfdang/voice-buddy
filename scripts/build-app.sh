#!/usr/bin/env bash
# Voice Buddy - Build script wrapper
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build.sh" "$@"
