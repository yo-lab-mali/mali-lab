# Test matrix

## P0

| Area | Core question |
|---|---|
| memory/VMA | Does backing outlive all CPU/GPU references? |
| mmap | Are cookies and VMA lifecycle transitions consistent? |
| User IO | Can queue User IO mapping outlive its owner? |
| CSF teardown | Can queue/group state become inconsistent? |
| imports | Do pin/map/unmap/free lifetimes remain valid? |

## P1

| Area | Core question |
|---|---|
| KCPU | Can deferred commands outlive referenced objects? |
| CQS/fences | Do wait/signal dependencies survive teardown? |
| SAME_VA/alias | Are CPU/GPU mappings and lifetimes coherent? |

## P2

JIT/tiler, real MMU faults, power transitions.

## P3

Firmware static analysis.
