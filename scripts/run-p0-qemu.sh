#!/usr/bin/env bash
#
# run-p0-qemu.sh - run the full P0 suite in the guest and validate the result.
#
# The lab ships prebuilt under dist/, so this is a thin wrapper around the
# self-contained dist/run.sh. It copies the guest's result JSON into results/
# and runs the host-side validator, so 'make test-p0-qemu' keeps working from
# the repo root while the real boot logic lives in dist/run.sh.
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS="$ROOT/results/p0-qemu-results.json"
P0_TEST_TIMEOUT_SEC="${P0_TEST_TIMEOUT_SEC:-30}"
DIST_RESULTS="$ROOT/dist/.run/results/p0-results.json"

[[ "$P0_TEST_TIMEOUT_SEC" =~ ^[1-9][0-9]*$ ]] \
  || { echo "error: P0_TEST_TIMEOUT_SEC must be a positive integer" >&2; exit 1; }

set +e
P0_TEST_TIMEOUT_SEC="$P0_TEST_TIMEOUT_SEC" "$ROOT/dist/run.sh"
qemu_rc=$?
set -e

mkdir -p "$(dirname "$RESULTS")"
if [[ -f "$DIST_RESULTS" ]]; then
  cp "$DIST_RESULTS" "$RESULTS"
else
  cat > "$RESULTS" <<JSON
{"schema_version":2,"runner":"run-p0-qemu.sh","status":"infra_error","qemu_exit_code":$qemu_rc,"tests":[],"summary":{"pass":0,"skip":0,"fail":0,"timeout":0,"crash":0,"infra_error":1},"infrastructure_errors":[{"code":"guest_result_missing","message":"guest did not produce p0-results.json"}]}
JSON
fi

printf 'P0 guest results: %s\n' "$RESULTS"
cat "$RESULTS"

VALIDATOR="$ROOT/scripts/validate-p0-results.py"
VALIDATION_REPORT="$ROOT/results/p0-qemu-validation.json"
if [[ ! -x "$VALIDATOR" ]]; then
  cat > "$VALIDATION_REPORT" <<JSON
{"schema_version":1,"status":"infra_error","infrastructure_errors":[{"code":"validator_missing","message":"host-side P0 result validator is missing: $VALIDATOR"}]}
JSON
  echo "error: host-side P0 result validator is missing: $VALIDATOR" >&2
  exit 2
fi

set +e
python3 "$VALIDATOR" "$RESULTS"
validation_rc=$?
set -e
if [[ $validation_rc -ne 0 ]]; then
  cat > "$VALIDATION_REPORT" <<JSON
{"schema_version":1,"status":"infra_error","infrastructure_errors":[{"code":"result_validation_failed","message":"guest P0 result failed host-side schema/consistency validation","result":"$RESULTS"}]}
JSON
  echo "error: guest P0 result failed host-side validation; see $VALIDATION_REPORT" >&2
  exit 2
fi

cat > "$VALIDATION_REPORT" <<JSON
{"schema_version":1,"status":"pass","result":"$RESULTS","message":"guest P0 result passed host-side validation"}
JSON

# A clean QEMU exit and a valid guest result are required before the run can
# be marked successful. Test failures remain represented inside the JSON.
if [[ $qemu_rc -ne 0 ]]; then
  exit "$qemu_rc"
fi
exit 0
