#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/tests"

if [[ ! -x "$BIN/001_alloc_free" ]]; then
  echo "P0 binaries are missing; run 'make tests' first." >&2
  exit 1
fi

fail=0
skip=0
for t in \
  001_alloc_free \
  002_alloc_mmap \
  003_mmap_unmap \
  004_free_before_unmap \
  001_cookie_lifecycle \
  003_vma_lifecycle \
  001_queue_bind \
  002_user_io_map; do
  case "$t" in
    001_alloc_free|002_alloc_mmap|003_mmap_unmap|004_free_before_unmap) group=memory ;;
    001_cookie_lifecycle|003_vma_lifecycle) group=mmap ;;
    *) group=user_io ;;
  esac
  echo "===== P0 $group/$t ====="
  "$BIN/$t"
  rc=$?
  case $rc in
    0) ;;
    77) skip=$((skip+1)) ;;
    *) fail=$((fail+1)) ;;
  esac
done

echo "P0 summary: failures=$fail skipped=$skip"
(( fail == 0 ))
