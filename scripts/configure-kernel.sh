#!/usr/bin/env bash
#
# configure-kernel.sh - retained entry point, delegates to the working stage.
#
# This script used to copy the No-Mali fragment straight to .config and then run
# olddefconfig. That cannot work. olddefconfig assigns every symbol the fragment
# does not mention its Kconfig default, so a bare fragment produces a near-empty
# kernel and drivers/gpu/arm/midgard/Kbuild aborts with $(error) on missing
# CONFIG_DMA_SHARED_BUFFER, CONFIG_PM_DEVFREQ, CONFIG_FW_LOADER and friends.
#
# The working order is defconfig, then the fragment, then olddefconfig, followed
# by the gate that asserts those symbols survived. That logic now lives in one
# place. See docs/build.md.
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "configure-kernel.sh: delegating to scripts/build-r54p0-kernel.sh config gate"
exec "$ROOT/scripts/build-r54p0-kernel.sh" config gate
