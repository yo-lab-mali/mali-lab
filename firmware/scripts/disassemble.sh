#!/usr/bin/env bash
set -euo pipefail
BIN="${1:?binary section}"
command -v arm-linux-gnueabihf-objdump >/dev/null || { echo "objdump missing"; exit 1; }
arm-linux-gnueabihf-objdump -D -b binary -m armv7e-m -Mforce-thumb "$BIN"
