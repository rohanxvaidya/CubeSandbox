#!/bin/bash

# based on numa node0 memory, and with
#numactl -m 0 ./dsa_memcpy_latency -m -b 16384 -s 1073741824 -i 10000000 -k 6 -w -q /dev/dsa/wq0.0 -o 1 -D 0 -I 1 -S 10 -C 0 -T 15000 -L 1 -g 1 -P -W


#numactl -m 0 ./dsa_memcpy_latency -d /dev/dax8.0 -b 16384 -s 1073741824 -i 10000000 -k 16 -w -q /dev/dsa/wq0.0 -o 1 -D 0 -I 1 -S 20 -C 0 -T 150000 -L 1 -g 1 -P -W 1 -I 1 -Q

# based on numa node0 memory, and with clx device /dev/dax8.0, on cpu 16. -w write to dax device with DSA wq0.0. 
# only show large than 150us latency operations. and test with light mode with 1 operation and 1x 20 us waiting 
numactl -m 0 ./dsa_memcpy_latency -d /dev/dax8.0 -b 16384 -s 1073741824 -i 10000000 -k 16 -w -q /dev/dsa/wq0.0 -o 1 -D 0 -I 1 -S 20 -C 0 -T 150000 -L 1 -g 1 -P -W 1 -I 1

# enable dedicated wq and enable verify data for test
numactl -m 0 ./dsa_memcpy_latency -d /dev/dax8.0 -b 16384 -s 1073741824 -i 10000000 -k 16 -w -q /dev/dsa/wq0.0 -o 1 -D 0 -I 1 -S 20 -C 0 -T 150000 -L 1 -g 1 -P -W 1 -I 1 -Q -v
