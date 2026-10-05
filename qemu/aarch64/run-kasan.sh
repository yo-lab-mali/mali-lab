#!/usr/bin/env bash
set -euo pipefail
echo "Use the KASAN kernel config, rebuild, then boot qemu/aarch64/run.sh."
exec "$(dirname "$0")/run.sh"
