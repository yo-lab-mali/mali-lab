# Guest-side P0 QEMU runner

`scripts/run-p0-qemu.sh` boots the configured AArch64 QEMU guest, exposes the
prebuilt P0 binaries through QEMU virtio-9p, runs them inside the guest against
`/dev/mali0`, and copies a JSON result file back to `results/p0-qemu-results.json`.

## Flow

```text
dist/bin  (8 prebuilt aarch64 binaries)
      |
      | QEMU virtio-9p (dist/.run/bin)
      v
/mnt/mali-p0/bin  ---> /dev/mali0
      |
      v
/mnt/mali-p0/results/p0-results.json
      |
      v
results/p0-qemu-results.json
```

The real work lives in the self-contained `dist/run.sh`; `scripts/run-p0-qemu.sh`
layers the guest result JSON and host-side validation on top. This replaced the
old runner that cross-compiled into `build/tests-aarch64` on every invocation.
`dist/run.sh` always passes `-dtb dist/virt-mali.dtb` and uses QEMU `-snapshot`
so the decompressed rootfs is opened copy-on-write and never mutated.

The rootfs must contain `rootfs/overlay/usr/local/bin/mali-p0-guest` and the
kernel must have 9p/virtio support. The supplied AArch64 config enables
`CONFIG_NET_9P`, `CONFIG_NET_9P_VIRTIO`, and `CONFIG_9P_FS`.

## Run

```bash
./scripts/run-p0-qemu.sh     # validates + writes results/
./dist/run.sh                # same boot, no validation step
make test-p0-qemu            # repo target for the above
```

Set the per-test timeout (default: 30 seconds):

```bash
P0_TEST_TIMEOUT_SEC=60 ./scripts/run-p0-qemu.sh
```

`dist/run.sh` also honours `P0_TEST_TIMEOUT_SEC`. There is no `QEMU_DTB` hook on
it: the DTB is part of the shipped lab and is always passed, because the No-Mali
driver only probes against a DTB that carries the `arm,mali-midgard` node.
Stock QEMU's `virt` machine does not emulate a real Mali GPU; the tests exercise
the driver's own bookkeeping.

## Result schema

The result is JSON with:

- `schema_version` (currently `2`)
- `runner`
- `status`: `pass`, `fail`, or `infra_error`
- `tests[]`: test name, status, exit code, duration, timeout, signal/error fields, guest log path
- `summary`: pass/skip/fail/timeout/crash/infra_error counts
- `infrastructure_errors[]`: explicit runner/payload errors with `code` and `message`
- Test statuses: `pass`, `skip`, `fail`, `timeout`, `crash`, `infra_error`
- `timeout` means the runner terminated a test after its per-test deadline. `crash` means the test exited with a signal-style status (`128 + signal`).
- `infra_error` is reserved for runner/test-payload problems such as missing binaries or a missing guest result file; these are recorded explicitly rather than as ordinary test failures.
- `environment`: kernel, architecture, Mali module version, device

Exit status is zero only when all executed tests pass/skip and no infrastructure, timeout, crash, or ordinary test failure occurred. Test skips are not failures. Missing binaries, payload-mount failures, and missing guest results are infrastructure errors.


## Host-side result validation

After QEMU exits, `scripts/run-p0-qemu.sh` validates the guest JSON with
`scripts/validate-p0-results.py` before returning success. The validator checks:

- `schema_version`, top-level status, runner, and required arrays/objects
- the complete expected P0 test set with no duplicate or unexpected tests
- every per-test status and exit-code invariant
- `timeout_sec` / `timed_out` consistency and timeout signal (`SIGTERM`/`SIGKILL`)
- crash signal presence and valid signal names
- non-crash tests do not carry a signal
- exact summary counters versus the per-test statuses
- infrastructure-error objects have non-empty `code` and `message` fields
- `summary.infra_error` exactly matches the number of infrastructure-error records
- top-level `status` agrees with the summary (`pass`, `fail`, or `infra_error`)

A validation failure is treated as a host infrastructure error and returns exit
code `2`; the run is never marked successful. A small machine-readable host
validation report is written to `results/p0-qemu-validation.json`.

Direct validation is also available for an existing result:

```bash
make validate-p0-results RESULTS=results/p0-qemu-results.json
```
