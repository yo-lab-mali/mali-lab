# Stateful fuzzing

Prefer valid state-machine transitions plus unusual ordering over random IOCTL
bytes. Keep each generated sequence reproducible with a seed.
