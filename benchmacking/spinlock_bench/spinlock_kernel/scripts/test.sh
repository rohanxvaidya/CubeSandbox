#!/bin/bash
# test tool to do memory sweep from based_addr to based_addr+offset for spinlock address pin
# test: test.sh 1ff000000 10000,  means based on 0x1ff000000, size is 0x10000

# Check if the correct number of arguments is provided
if [ $# -ne 2 ]; then
  echo "Usage: $0 <base_address_hex> <size_hex>"
  exit 1
fi

# Input parameters
base_address_hex="$1"
size_hex="$2"

# #Remove the "0x" prefix if present
# # Check if the input parameters have the "0x" prefix
# if [[ ! "$base_address_hex" =~ ^0x[0-9a-fA-F]+$ ]]; then
#   echo "Error: Base address must have the '0x' prefix and be a valid hexadecimal number."
#   exit 1
# fi

# if [[ ! "$size_hex" =~ ^0x[0-9a-fA-F]+$ ]]; then
#   echo "Error: Size must have the '0x' prefix and be a valid hexadecimal number."
#   exit 1
# fi

# base_address_hex="${base_address_hex#0x}"
# size_hex="${size_hex#0x}"

# Convert hexadecimal to decimal
base_address=$((0x$base_address_hex))
size=$((0x$size_hex))

# Check for errors
if [ $base_address -lt 0 ]; then
  echo "Error: Base address must be non-negative."
  exit 1
fi

if [ $size -le 0 ]; then
  echo "Error: Size must be greater than zero."
  exit 1
fi

# Scan step
step=256

# Loop through the memory range
for (( address=$base_address; address<$base_address+$size; address+=$step )); do

  offset=$((address - base_address))
  printf "Scanning address: 0x%x, Offset: 0x%x\n" "$address" "$offset"

  h_offset=0x$(echo "ibase=10;obase=16;$offset" |bc)

  echo $h_offset > /sys/kernel/spinlock_bench/lock_address_offset

  cat /sys/kernel/spinlock_bench/lock_phy_address
  #bash -x ./bench_spinlock.sh -t 32 -c FFffFFFF -d 16 -r 1

done

exit 0