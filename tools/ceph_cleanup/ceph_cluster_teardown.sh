#!/bin/bash -e
## Clean up the disk for teardown the ceph cluster for next time build.
## run the script with drive name, e.g., ceph_cluster.teardown.sh /dev/sdb 
##
# example DISK="/dev/sdb"

DISK=$1
IS_HDD=FALSE

if [ -z "$DISK" ]; then
    echo "Error: Please select a specific drive to clean up!"
    exit -1;
fi

# Zap the disk to a fresh, usable state (zap-all is important, b/c MBR has to be clean)

# You will have to run this step for all disks.
sgdisk --zap-all $DISK

if [ ${IS_HDD} == TRUE ]; then
    echo "Clean hdds with dd."
    dd if=/dev/zero of="$DISK" bs=1M count=100 oflag=direct,dsync
else
    echo "clean SSD drives"
    # Clean disks such as ssd with blkdiscard instead of dd
    blkdiscard $DISK
fi
# These steps only have to be run once on each node
# If rook sets up osds using ceph-volume, teardown leaves some devices mapped that lock the disks.
ls /dev/mapper/ceph-* | xargs -I% -- dmsetup remove %

# ceph-volume setup can leave ceph-<UUID> directories in /dev and /dev/mapper (unnecessary clutter)
rm -rf /dev/ceph-*
rm -rf /dev/mapper/ceph--*

# Inform the OS of partition table changes
partprobe $DISK



