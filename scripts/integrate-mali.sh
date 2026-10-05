#!/usr/bin/env bash
#
# integrate-mali.sh - retained entry point, delegates to the working stage.
#
# Was a placeholder that only printed instructions. scripts/build-r54p0-kernel.sh
# now performs the integration for real: it unpacks the MD5-verified r54p0
# archive resolved through configs/r54p0.env, copies
# driver/product/kernel into the tree, and wires drivers/gpu/Makefile and
# drivers/video/Kconfig. See docs/build.md.
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "integrate-mali.sh: delegating to scripts/build-r54p0-kernel.sh integrate"
exec "$ROOT/scripts/build-r54p0-kernel.sh" integrate
