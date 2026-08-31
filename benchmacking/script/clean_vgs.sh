#!/bin/bash
VGS=$(sudo vgs |grep -v grep |grep ceph-|awk '{print $1}')
for I in $VGS;do
    sudo vgremove -y $I
done

if [ $? -ne 0 ] ; then
    echo "faild"
else
    echo "success"
fi

sgdisk --zap-all /dev/nvme1n1 && sgdisk --zap-all /dev/nvme2n1 && sgdisk --zap-all /dev/nvme3n1 && sgdisk --zap-all /dev/nvme4n1 && sgdisk --zap-all /dev/nvme5n1 && sgdisk --zap-all /dev/nvme6n1 && sgdisk --zap-all /dev/nvme7n1 
