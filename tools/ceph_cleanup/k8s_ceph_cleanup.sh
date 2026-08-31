#!/bin/bash

sudo kubeadm reset

sudo systemctl stop kubelet
sudo systemctl stop docker
sudo rm -rf /var/lib/cni/ /var/lib/kubelet/* /etc/cni/
sudo ifconfig cni0 down
sudo ifconfig docker0 down
sudo ip link delete cni0
sudo ip link delete flannel.1 down
sudo systemctl daemon-reload
sudo systemctl start docker.service

sudo rm -rf $HOME/.kube/config

sudo rm -rf /var/lib/rook

sudo ./ceph_cluster_teardown.sh /dev/sdd
sudo ./ceph_cluster_teardown.sh /dev/sdc
sudo ./ceph_cluster_teardown.sh /dev/sdb
