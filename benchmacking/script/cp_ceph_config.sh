#! /bin/bash
kubectl cp $(kubectl get po -n rook-ceph |grep rook-ceph-tool |awk '{print $1}'):/etc/ceph/ceph.conf /etc/ceph/ceph.conf -n rook-ceph
kubectl cp $(kubectl get po -n rook-ceph |grep rook-ceph-tool |awk '{print $1}'):/etc/ceph/keyring  /etc/ceph/keyring  -n rook-ceph

