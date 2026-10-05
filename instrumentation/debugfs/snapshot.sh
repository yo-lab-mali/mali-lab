#!/usr/bin/env bash
set -euo pipefail
exec "$(dirname "$0")/collect.sh" "${1:-/tmp/mali-debugfs}"
