#!/usr/bin/env bash
set -euo pipefail
BIN="${1:?firmware binary}"
file "$BIN"
