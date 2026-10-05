#!/usr/bin/env bash
set -euo pipefail
"$(dirname "$0")/verify-r54p0.sh"
"$(dirname "$0")/integrate-mali.sh"
"$(dirname "$0")/configure-kernel.sh"
"$(dirname "$0")/build-kernel.sh"
"$(dirname "$0")/build-rootfs.sh"
"$(dirname "$0")/build-tests.sh"
