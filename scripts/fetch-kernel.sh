#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/work"
if [[ -d "$ROOT/work/linux/.git" ]]; then
  echo "Linux tree already present."
  exit 0
fi
echo "Place/clone the desired Linux kernel tree at work/linux."
echo "This script intentionally does not choose a kernel version for you."
