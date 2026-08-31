#!/bin/bash
set -x

#gcc dsa_memcpy_latency.cpp -o dsa_memcpy_latency  -l accel-config -I /usr/include -lpmem
gcc dsa_memcpy_latency.cpp -o dsa_memcpy_latency  -lpmem
