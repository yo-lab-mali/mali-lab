#!/usr/bin/env python3
"""Strict host-side validator for guest P0 JSON results."""
import json
import sys
from pathlib import Path

EXPECTED_TESTS = [
    "memory/001_alloc_free",
    "memory/002_alloc_mmap",
    "memory/003_mmap_unmap",
    "memory/004_free_before_unmap",
    "mmap/001_cookie_lifecycle",
    "mmap/003_vma_lifecycle",
    "user_io/001_queue_bind",
    "user_io/002_user_io_map",
]
STATUSES = {"pass", "skip", "fail", "timeout", "crash", "infra_error"}
OVERALL_STATUSES = {"pass", "fail", "infra_error"}
SIGNALS = {
    "SIGHUP", "SIGINT", "SIGQUIT", "SIGILL", "SIGABRT", "SIGFPE",
    "SIGKILL", "SIGSEGV", "SIGPIPE", "SIGALRM", "SIGTERM", "SIGBUS",
    "SIGSYS", "SIGTRAP", "SIGXCPU", "SIGXFSZ", "SIGUSR1", "SIGUSR2",
}
SUMMARY_KEYS = ["pass", "skip", "fail", "timeout", "crash", "infra_error"]


def err(errors, path, message):
    errors.append(f"{path}: {message}")


def require_type(errors, obj, key, typ, path):
    if key not in obj:
        err(errors, path, f"missing required field {key!r}")
        return None
    value = obj[key]
    if not isinstance(value, typ) or (typ is int and isinstance(value, bool)):
        err(errors, f"{path}.{key}", f"expected {typ.__name__}, got {type(value).__name__}")
        return None
    return value


def validate(path):
    errors = []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        return [f"$: invalid JSON: {exc}"]

    if not isinstance(data, dict):
        return ["$: top-level JSON value must be an object"]

    schema = require_type(errors, data, "schema_version", int, "$")
    if isinstance(schema, int) and schema != 2:
        err(errors, "$.schema_version", f"expected 2, got {schema}")

    runner = require_type(errors, data, "runner", str, "$")
    if isinstance(runner, str) and not runner:
        err(errors, "$.runner", "must not be empty")

    overall = require_type(errors, data, "status", str, "$")
    if isinstance(overall, str) and overall not in OVERALL_STATUSES:
        err(errors, "$.status", f"invalid status {overall!r}")

    tests = require_type(errors, data, "tests", list, "$")
    summary = require_type(errors, data, "summary", dict, "$")
    infra_errors = require_type(errors, data, "infrastructure_errors", list, "$")

    if tests is not None:
        seen = set()
        counts = {key: 0 for key in SUMMARY_KEYS}
        for i, test in enumerate(tests):
            p = f"$.tests[{i}]"
            if not isinstance(test, dict):
                err(errors, p, "must be an object")
                continue

            name = require_type(errors, test, "name", str, p)
            status = require_type(errors, test, "status", str, p)
            exit_code = require_type(errors, test, "exit_code", int, p)
            duration = require_type(errors, test, "duration_ms", int, p)
            timeout_sec = require_type(errors, test, "timeout_sec", int, p)
            timed_out = require_type(errors, test, "timed_out", bool, p)
            signal = require_type(errors, test, "signal", str, p)
            error_text = require_type(errors, test, "error", str, p)
            log = require_type(errors, test, "log", str, p)

            if isinstance(name, str):
                if name in seen:
                    err(errors, f"{p}.name", f"duplicate test {name!r}")
                seen.add(name)
                if name not in EXPECTED_TESTS:
                    err(errors, f"{p}.name", f"unexpected test {name!r}")

            if isinstance(status, str):
                if status not in STATUSES:
                    err(errors, f"{p}.status", f"invalid status {status!r}")
                else:
                    counts[status] += 1

            if isinstance(exit_code, int) and not isinstance(exit_code, bool):
                if exit_code < 0 or exit_code > 255:
                    err(errors, f"{p}.exit_code", "must be in range 0..255")

            if isinstance(duration, int) and not isinstance(duration, bool) and duration < 0:
                err(errors, f"{p}.duration_ms", "must be non-negative")

            if isinstance(timeout_sec, int) and not isinstance(timeout_sec, bool) and timeout_sec <= 0:
                err(errors, f"{p}.timeout_sec", "must be positive")

            if isinstance(signal, str) and signal and signal not in SIGNALS:
                err(errors, f"{p}.signal", f"unknown signal name {signal!r}")

            if isinstance(status, str) and isinstance(timed_out, bool) and isinstance(signal, str):
                if status == "timeout":
                    if not timed_out:
                        err(errors, p, "timeout status requires timed_out=true")
                    if signal not in {"SIGTERM", "SIGKILL"}:
                        err(errors, f"{p}.signal", "timeout must record SIGTERM or SIGKILL")
                else:
                    if timed_out:
                        err(errors, p, "only timeout status may set timed_out=true")
                    if status == "crash" and not signal:
                        err(errors, f"{p}.signal", "crash status requires a signal")
                    if status != "crash" and signal:
                        err(errors, f"{p}.signal", f"signal must be empty for status {status!r}")

            if isinstance(status, str) and isinstance(exit_code, int):
                if status == "pass" and exit_code != 0:
                    err(errors, p, "pass status requires exit_code=0")
                if status == "skip" and exit_code != 77:
                    err(errors, p, "skip status requires exit_code=77")
                if status == "crash" and not (129 <= exit_code <= 255):
                    err(errors, p, "crash status requires exit_code in 129..255")
                if status == "timeout" and exit_code not in range(129, 256):
                    err(errors, p, "timeout status requires signal-style exit_code 129..255")

        if set(seen) != set(EXPECTED_TESTS):
            missing = sorted(set(EXPECTED_TESTS) - seen)
            if missing:
                err(errors, "$.tests", f"missing expected tests: {', '.join(missing)}")

        if summary is not None:
            for key in SUMMARY_KEYS:
                value = require_type(errors, summary, key, int, "$.summary")
                if isinstance(value, int) and not isinstance(value, bool) and value < 0:
                    err(errors, f"$.summary.{key}", "must be non-negative")
                if isinstance(value, int) and not isinstance(value, bool) and value != counts[key]:
                    err(errors, f"$.summary.{key}", f"expected {counts[key]}, got {value}")

    if infra_errors is not None:
        for i, item in enumerate(infra_errors):
            p = f"$.infrastructure_errors[{i}]"
            if not isinstance(item, dict):
                err(errors, p, "must be an object")
                continue
            code = require_type(errors, item, "code", str, p)
            message = require_type(errors, item, "message", str, p)
            if isinstance(code, str) and not code:
                err(errors, f"{p}.code", "must not be empty")
            if isinstance(message, str) and not message:
                err(errors, f"{p}.message", "must not be empty")

    if summary is not None and isinstance(overall, str):
        infra_count = summary.get("infra_error")
        bad_tests = sum(summary.get(k, 0) for k in ("fail", "timeout", "crash")) if all(k in summary and isinstance(summary[k], int) for k in SUMMARY_KEYS) else None
        if isinstance(infra_count, int):
            if infra_count > 0 and overall != "infra_error":
                err(errors, "$.status", "infra_error count > 0 requires status=infra_error")
            elif infra_count == 0 and bad_tests == 0 and overall != "pass":
                err(errors, "$.status", "all tests pass/skip requires status=pass")
            elif infra_count == 0 and bad_tests > 0 and overall != "fail":
                err(errors, "$.status", "test failure/timeout/crash requires status=fail")

    if summary is not None and infra_errors is not None:
        infra_count = summary.get("infra_error")
        if isinstance(infra_count, int) and infra_count != len(infra_errors):
            err(errors, "$.infrastructure_errors", f"length must equal summary.infra_error ({infra_count}), got {len(infra_errors)}")

    return errors


def main(argv):
    if len(argv) != 2:
        print(f"usage: {argv[0]} RESULTS.json", file=sys.stderr)
        return 2
    path = Path(argv[1])
    if not path.is_file():
        print(f"INVALID: missing result file: {path}", file=sys.stderr)
        return 2
    errors = validate(path)
    if errors:
        print(f"INVALID P0 results: {path}", file=sys.stderr)
        for item in errors:
            print(f"  - {item}", file=sys.stderr)
        return 1
    print(f"VALID P0 results: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
