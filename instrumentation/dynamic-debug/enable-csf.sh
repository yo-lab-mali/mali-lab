#!/usr/bin/env bash
set -euo pipefail
echo 'file drivers/gpu/arm/midgard/mali_kbase_csf_*.c +p' > /sys/kernel/debug/dynamic_debug/control 2>/dev/null || true
