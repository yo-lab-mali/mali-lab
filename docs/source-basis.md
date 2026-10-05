# Source basis

This repository follows the supplied Arm Mali documentation for:

- r54p0 5th Gen driver integration
- No-Mali/dummy model
- Device Tree and simulated-platform approaches
- CSF queues and User IO
- GPU memory, mmap and VMA behavior
- KCPU queues and synchronization
- firmware static-analysis limitations

Where the documents do not establish that QEMU implements a real Mali GPU, this
repository does not assume it. QEMU is treated as the VM environment for driver
research.

The exact source archive must be obtained from the appropriate Arm distribution
channel and verified before integration.
