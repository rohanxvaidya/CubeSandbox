#/bin/bash

## How to run:
# numactl -C 64-79,192-207 -m 1 ./ob_cas_timestamp -w 32 -t 150000 -m 30 -s 80 -d 120 -M 31 -W 0 -l spin -i 4 


gcc -O3 -std=c11 -pthread oceanbase_atomic_cas_timestamp.c -o ob_cas_timestamp
