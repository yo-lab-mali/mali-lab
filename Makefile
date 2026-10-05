SHELL := /bin/bash
ROOT := $(CURDIR)
RESULTS ?= results/p0-qemu-results.json

.PHONY: bootstrap verify fetch-kernel fetch-mali integrate config build rootfs tests all run clean test-p0 test-p0-qemu validate-p0-results test-p1 report

bootstrap:
	./scripts/bootstrap-host.sh

verify:
	./scripts/verify-r54p0.sh

fetch-kernel:
	./scripts/fetch-kernel.sh

fetch-mali:
	./scripts/fetch-mali.sh

integrate:
	./scripts/integrate-mali.sh
	./scripts/apply-patches.sh

config:
	./scripts/configure-kernel.sh

build:
	./scripts/build-kernel.sh

rootfs:
	./scripts/build-rootfs.sh

tests:
	./scripts/build-tests.sh

all:
	./scripts/build-all.sh

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
