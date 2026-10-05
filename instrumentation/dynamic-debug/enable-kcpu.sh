#!/usr/bin/env bash
set -euo pipefail
echo 'module mali_kbase +p' > /sys/kernel/debug/dynamic_debug/control
