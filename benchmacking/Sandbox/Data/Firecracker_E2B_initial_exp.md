# Firecracker E2B Initial Experiment

| Runtime SW | system config | test model | Ready Checkpoint | Concurrency | Samples | Avg Latency | Tail Latency | Total Time | Throughput |
|---|---|---|---|---:|---:|---|---|---|---|
| Firecracker | HEX Full System | create-delete | boottimer | 50 | 4000 | 163.91ms | max 404ms | 55.710s | 71.8/s |
| Firecracker | HEX Full System | create-only | boottimer | 8 | 2000 | 163.31ms | 250ms | 66.074 |  |
| Firecracker | SNC Mode (single node) | create-delete | boottimer | 40 | 4000 | 139.25ms | max 391ms | 63.2s | 63.3/s |
| Firecracker | SNC Mode (single node) | create-delete | boottimer | 50 | 4000 | 175.70ms | max 469ms | 55.6s | 71.9/s |
| Firecracker | SNC Mode (single node) | create-delete | boottimer | 55 | 4000 | 212.07ms | max 494ms | 52.8s | 75.8/s |
| Firecracker | SNC Mode (single node) | create-only | boottimer | 8 | 1800 | 177.35ms | max 904ms | 61.0s | 29.5/s |
| E2B | HEX Full System | create-delete | envd ready | 6 | 900 | 145ms | p99 381ms | 70.258s | 12.8/s |
| E2B | HEX Full System | create-delete | envd ready | 8 | 960 | 184ms | p99 465ms | 74.585s | 12.9/s |
| E2B | HEX Full System | create-delete | envd ready | 10 | 500 | 248ms | p99 869ms | 45.719s | 10.9/s |
| E2B | SNC Mode (single node) | create-delete | envd ready | 9 | 639 | 188ms | p99 676ms | 51.898s | 12.3/s |
