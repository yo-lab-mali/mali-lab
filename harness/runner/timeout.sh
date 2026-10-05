#!/usr/bin/env bash
set -euo pipefail
exec timeout "${TIMEOUT:-30}" "$@"
