#!/usr/bin/env bash
set -euo pipefail
TEST="${1:?test binary required}"
TIMEOUT="${TIMEOUT:-30}"
timeout "$TIMEOUT" "$TEST"
