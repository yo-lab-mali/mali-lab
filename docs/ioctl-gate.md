# ioctl gate

Kbase gates its ioctl surface on per-file setup state. This is the single most common
reason a correctly written test fails for a reason unrelated to the behaviour it is
testing, so it is documented separately from `docs/abi-check.md`.

## The rule

```text
open("/dev/mali0")
  -> KBASE_IOCTL_VERSION_CHECK   (nr 52,  CSF UAPI header)
  -> KBASE_IOCTL_SET_FLAGS       (nr 1,   core UAPI header)
  -> everything else
```

`kbase_ioctl()` dispatches only a small set before the gate:

- `KBASE_IOCTL_VERSION_CHECK`
- `KBASE_IOCTL_VERSION_CHECK_RESERVED` (always returns `-EPERM`)
- `KBASE_IOCTL_SET_FLAGS`
- `KBASE_IOCTL_KINSTR_PRFCNT_ENUM_INFO`
- `KBASE_IOCTL_KINSTR_PRFCNT_SETUP`
- `KBASE_IOCTL_GET_GPUPROPS`

Everything else then requires `kbase_file_get_kctx_if_setup_complete()` to return a
non-NULL context. A freshly opened fd holds neither an API version nor a context, so
it returns NULL and the ioctl fails with **`-EPERM`**.

## `-EPERM`, not `-ENOTTY`

The distinction matters when reading logs. The documented `-ENOTTY` / `-ENOIOCTLCMD`
behaviour corresponds to an *unrecognised* ioctl number (`Unknown ioctl 0x%x nr:%d`
followed by `-ENOIOCTLCMD`). A recognised ioctl issued too early gives `-EPERM`.

So:

| Symptom | Meaning |
|---|---|
| `-EPERM` on every ioctl | handshake missing or incomplete |
| `-ENOIOCTLCMD` | ioctl number not known to this driver — wrong headers or wrong ioctl |
| `-EINVAL` from `KBASE_IOCTL_SET_FLAGS` | `create_flags` had bits outside `BASEP_CONTEXT_CREATE_KERNEL_FLAGS` |

## Where VERSION_CHECK lives

`KBASE_IOCTL_VERSION_CHECK` is defined in
`include/uapi/gpu/arm/midgard/csf/mali_kbase_csf_ioctl.h`, **not** in
`mali_kbase_ioctl.h`. `KBASE_IOCTL_SET_FLAGS` is in the core header. Reading only the
core header makes it easy to believe no handshake is needed.

## Version negotiation

```c
struct kbase_ioctl_version_check version = {
    .major = BASE_UK_VERSION_MAJOR,
    .minor = BASE_UK_VERSION_MINOR,
};
ioctl(fd, KBASE_IOCTL_VERSION_CHECK, &version);
```

Per `kbase_api_handshake()`:

- If `major` matches the driver's, `minor` is clamped **down** to
  `BASE_UK_VERSION_MINOR` and returned.
- If `major` does not match, the driver returns **its own** version regardless.

Either way the reply is authoritative, so userspace must read it back rather than
assume its request was granted. Requesting a higher version than available is allowed;
the driver simply reports what it has.

`mali_open()` in `tests/common/test_common.c` performs this handshake and validates the
returned major, exposing the reason via `mali_open_reason()`. `BASE_UK_VERSION_MINOR`
is also asserted `>= 35` in the ABI check, because User-IO page allocation moves from
bind-time to CSG-create-time at that version.

## Context creation

For a version that supports system monitor (r54p0 at `1.36` qualifies), `SET_FLAGS`
creates the Kbase context via `kbase_file_create_kctx()`. `VERSION_CHECK` alone
creates it only for older, pre-system-monitor versions, with job submission disabled.

`create_flags` must be a subset of `BASEP_CONTEXT_CREATE_KERNEL_FLAGS`
(`BASE_CONTEXT_SYSTEM_MONITOR_SUBMIT_DISABLED` plus the MMU group ID mask). Anything
else is `-EINVAL`. On CSF GPUs the legacy job-manager submission path stays disabled.

## Padding is validated

Several ioctls run a `check_padding_*()` helper before dispatch and reject non-zero
padding bytes with `-EINVAL`. `KBASE_IOCTL_CS_QUEUE_GROUP_CREATE` is one of them:
`in.padding[62]` must be zero. Zero-initialising the union satisfies this.

`KBASE_IOCTL_CS_QUEUE_BIND` is the opposite case — the driver zeroes
`in.padding[]` on userspace's behalf for backward compatibility, and the check is
deferred pending GPUCORE-42000.
