#!/usr/bin/env bash
set -euo pipefail
echo 'file drivers/gpu/arm/midgard/mali_kbase_mem_linux.c +p' > /sys/kernel/debug/dynamic_debug/control
