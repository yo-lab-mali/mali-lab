SHELL := /bin/bash
ROOT := $(CURDIR)
RESULTS ?= results/p0-qemu-results.json

.PHONY: bootstrap verify fetch-kernel fetch-mali integrate config build kernel \
        dtb rootfs tests all run clean test-p0 test-p0-qemu \
        validate-p0-results test-p1 report dist run-dist manual-test

# scripts/build-r54p0-kernel.sh owns the kernel pipeline. The per-stage scripts
# under scripts/ are thin delegators kept so existing entry points keep working;
# the logic lives in one place so it cannot drift. Override KVER to change the
# pinned kernel (default 6.6.158).

bootstrap:
	./scripts/bootstrap-host.sh

verify:
	./scripts/verify-r54p0.sh

fetch-kernel:
	./scripts/build-r54p0-kernel.sh fetch

fetch-mali:
	./scripts/fetch-mali.sh

integrate:
	./scripts/build-r54p0-kernel.sh integrate
	./scripts/apply-patches.sh

config:
	./scripts/build-r54p0-kernel.sh config gate

build:
	./scripts/build-r54p0-kernel.sh build

# The whole kernel in one step: fetch, integrate, config, gate, build.
kernel:
	./scripts/build-r54p0-kernel.sh

# Required for the driver to probe. Without a Mali node in the DTB the module
# loads but never binds, so /dev/mali0 never appears. See qemu/aarch64/run.sh.
dtb:
	./qemu/aarch64/dumpdtb.sh

rootfs:
	./scripts/build-rootfs.sh

tests:
	./scripts/build-tests.sh

all:
	./scripts/build-all.sh

# Collect the build outputs into dist/, a self-contained folder that boots and
# runs the P0 suite with only qemu-system-aarch64 on the host. Once it is built,
# work/ (3.3 GB of rebuildable input) is no longer needed. See docs/build.md.
dist:
	./scripts/package-dist.sh

# Run the packaged lab. Works with no kernel tree and no sources present.
run-dist:
	./dist/run.sh

# Interactive manual testing - boots to a shell so you can inspect and run
# tests manually. Requires qemu-system-aarch64 on the host.
manual-test:
	./scripts/manual-test.sh

run:
	./scripts/boot-qemu.sh

test-p0:
	./scripts/run-p0.sh

test-p0-qemu:
	./scripts/run-p0-qemu.sh

validate-p0-results:
	python3 ./scripts/validate-p0-results.py $(RESULTS)

test-p1:
	@echo "Run compiled P1 suites: kcpu sync race"

report:
	./scripts/collect-artifacts.sh

clean:
	./scripts/clean.sh
