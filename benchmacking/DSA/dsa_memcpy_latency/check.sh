#!/bin/bash

# Find all DSA devices and print their NUMA node
for dsa in /sys/bus/pci/devices/*:*:*.*/; do
        if grep -q "0x0b25" "$dsa/device"; then
                node=$(cat "$dsa/numa_node")
                pci_bus=$(basename "$dsa")
                echo "Device $pci_bus is on NUMA Node $node"
		ls /sys/bus/pci/devices/$pci_bus/ |grep dsa

        fi
done



#!/bin/bash

echo "==============================================================="
echo "Intel DSA Device & PASID Status Report"
echo "Date: $(date)"
echo "==============================================================="

# Find all dsa devices and sort them numerically
#DSA_DEVICES=$(ls -d /sys/bus/dsa/devices/dsa* | sort -V)
#DSA_DEVICES=$(ls /sys/bus/dsa/devices/ | grep -E '^dsa[0-9]+$' | sort -V)
#DSA_DEVICES=$(find /sys/bus/dsa/devices/ -maxdepth 1 -regex ".*/dsa[0-9]+" | sort -V)

#for dsa in $DSA_DEVICES; do
#    echo $dsa
#    dev_name=$(basename $dsa)
#    echo $dev_name
#    /home/mz/dsa/dsa-perf-micros/scripts/setup_dsa.sh -d $dev_name -w 4 -m s -e 1


# Hard-coded for dsa0 only.
# Steps:
# 1) disable all WQs on dsa0
# 2) disable device dsa0
# 3) configure:
#    - dsa0/wq0.0: shared, group 0, block-on-fault=1, size=max_work_queues_size/4, threshold=size
#    - dsa0/wq0.1: dedicated, group 0, block-on-fault=1, size=max_work_queues_size/4
#    - assign exactly 1 engine to group 0 (engine0.0)
# 4) enable device + enable those WQs

if ! command -v accel-config >/dev/null 2>&1; then
  echo "ERROR: accel-config not found in PATH"
  exit 1
fi

SYSFS="/sys/bus/dsa/devices"

MAX_WQS="$(cat "${SYSFS}/dsa0/max_work_queues")"
MAX_ENGINES="$(cat "${SYSFS}/dsa0/max_engines")"
MAX_WQ_SIZE="$(cat "${SYSFS}/dsa0/max_work_queues_size")"
WQ_SIZE="$(( MAX_WQ_SIZE / 4 ))"

echo "dsa0: max_wqs=${MAX_WQS}, max_engines=${MAX_ENGINES}, max_work_queues_size=${MAX_WQ_SIZE}, per_wq_size=${WQ_SIZE}"

echo "== 1) disable all WQs on dsa0 =="
for ((i=0; i<MAX_WQS; i++)); do
  accel-config disable-wq "dsa0/wq0.${i}" 2>/dev/null || true
done

echo "== 2) disable device dsa0 =="
accel-config disable-device "dsa0" 2>/dev/null || true

echo "== 3) reset engines and configure WQs (wq0.0=shared, wq0.1=dedicated) =="

# Reset all engines to group -1 (clean state)
for ((i=0; i<MAX_ENGINES; i++)); do
  accel-config config-engine "dsa0/engine0.${i}" --group-id=-1
done

# Reset target WQs to known state
accel-config config-wq "dsa0/wq0.0" --wq-size=0 2>/dev/null || true
accel-config config-wq "dsa0/wq0.1" --wq-size=0 2>/dev/null || true

# Assign 1 engine to group 0 (hard-coded engine0.0)
accel-config config-engine "dsa0/engine0.0" --group-id=0

# wq0.0: shared
accel-config config-wq "dsa0/wq0.0" \
  --group-id=0 \
  --block-on-fault=1 \
  --mode=shared \
  --priority=10 \
  --wq-size="${WQ_SIZE}" \
  --type=user \
  --name=app0 \
  --driver-name=user
accel-config config-wq "dsa0/wq0.0" --threshold="${WQ_SIZE}"

# wq0.1: dedicated
accel-config config-wq "dsa0/wq0.1" \
  --group-id=0 \
  --block-on-fault=1 \
  --mode=dedicated \
  --priority=10 \
  --wq-size="${WQ_SIZE}" \
  --type=user \
  --name=app1 \
  --driver-name=user

echo "== 4) enable device and WQs =="
accel-config enable-device "dsa0"
accel-config enable-wq "dsa0/wq0.0"
accel-config enable-wq "dsa0/wq0.1"

echo "Done."
accel-config list-wq -d "dsa0" 2>/dev/null || true
#
#    state=$(cat "$dsa/state" 2>/dev/null || echo "unknown")
#    numa=$(cat "$dsa/numa_node" 2>/dev/null || echo "N/A")
#
#    echo "Device: $dev_name [State: $state, NUMA: $numa]"
#
#    # Check for Work Queues within this device
#    WQS=$(ls -d "$dsa/wq"* 2>/dev/null)
#
#    if [ -z "$WQS" ]; then
#        echo "  --> No Work Queues configured."
#    else
#        for wq in $WQS; do
#            wq_name=$(basename $wq)
#            wq_state=$(cat "$wq/state" 2>/dev/null)
#            wq_mode=$(cat "$wq/mode" 2>/dev/null)
#
#            # Check for PASID (The critical part for enqcmd)
#            if [ -f "$wq/pasid" ]; then
#                pasid=$(cat "$wq/pasid")
#            else
#                pasid="MISSING (SVA/Scalable Mode Inactive)"
#            fi
#
#            echo "  |- $wq_name: Mode=$wq_mode, State=$wq_state, PASID=$pasid"
#
#            # Check for shared mode specific constraints
#            if [[ "$wq_mode" == "shared" ]]; then
#                threshold=$(cat "$wq/threshold" 2>/dev/null)
#                size=$(cat "$wq/size" 2>/dev/null)
#                echo "     [Shared Config] Size: $size, Threshold: $threshold"
#            fi
#        done
#    fi
    echo "---------------------------------------------------------------"
#done

# Check global IOMMU Scalable Mode status
#echo "System-wide Scalable Mode Check:"
#if dmesg | grep -iq "Scalable mode enabled"; then
#    echo "  SUCCESS: IOMMU Scalable Mode is detected in dmesg."
#else
#    echo "  FAILURE: IOMMU Scalable Mode NOT found. enqcmd will fail."
#fi
