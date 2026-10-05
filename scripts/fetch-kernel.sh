#!/usr/bin/env bash
#
# fetch-kernel.sh - retained entry point, delegates to the working stage.
#
# Was a placeholder that refused to pick a kernel version. scripts/build-r54p0-kernel.sh
# pins a version (KVER, default 6.6.158 - the latest 6.6 LTS, inside the range
# r54p0's feature guards span), downloads it from kernel.org and unpacks it to
# work/linux. Override with KVER=... if a different pairing is needed.
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "fetch-kernel.sh: delegating to scripts/build-r54p0-kernel.sh fetch"
exec "$ROOT/scripts/build-r54p0-kernel.sh" fetch
