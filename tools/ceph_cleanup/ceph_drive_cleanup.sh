#!/bin/bash


sudo rm -rf /var/lib/rook

sudo ./ceph_cluster_teardown.sh /dev/sdd
sudo ./ceph_cluster_teardown.sh /dev/sdc
sudo ./ceph_cluster_teardown.sh /dev/sdb
