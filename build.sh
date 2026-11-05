#!/usr/bin/env bash
# Voice Buddy - Local Build entry point
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/build.sh" "$@"
