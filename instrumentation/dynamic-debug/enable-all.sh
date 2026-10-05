#!/usr/bin/env bash
set -euo pipefail
for f in "$(dirname "$0")"/enable-*.sh; do [ "$f" = "$0" ] || "$f" || true; done
