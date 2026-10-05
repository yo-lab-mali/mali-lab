#!/usr/bin/env bash
#
# build-kernel.sh - retained entry point, delegates to the working stage.
#
# Was `make Image modules dtbs` straight out of work/linux: it copied Image to
# build/kernel/ and nothing else, so the driver module was never published and
# the build ran with no check that the No-Mali symbols survived olddefconfig.
# A build that produced no mali_kbase.ko still exited 0.
#
# scripts/build-r54p0-kernel.sh build runs the config gate first, then copies
# both Image and mali_kbase.ko plus a manifest recording the exact kernel
# version and DDK archive used. See docs/build.md.
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "build-kernel.sh: delegating to scripts/build-r54p0-kernel.sh build"
exec "$ROOT/scripts/build-r54p0-kernel.sh" build
