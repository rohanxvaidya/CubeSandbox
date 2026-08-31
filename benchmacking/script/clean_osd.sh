#!/bin/bash
# rados df # ceph -s 等可用空间恢复 再删除osd
# ceph osd pool rm replicapool replicapool --yes-i-really-really-mean-it
# kubectl delete -f ../storageclass.yaml 
# sleep 30s
MGR=$(kubectl get po -n rook-ceph |grep rook-ceph-mgr |awk '{print $1}')
kubectl delete -n rook-ceph po/$MGR --force
if [ $? -ne 0 ] ; then
    echo "faild"
else
    echo "success"
fi

MON=$(kubectl get po -n rook-ceph |grep rook-ceph-mon |awk '{print $1}')
kubectl delete -n rook-ceph po/$MON --force
if [ $? -ne 0 ] ; then
    echo "faild"
else
    echo "success"
fi

OSD=$(kubectl get po -n rook-ceph |grep rook-ceph-osd |grep -v rook-ceph-osd-prepare-|awk '{print $1}')
for I in $OSD;do
    kubectl delete -n rook-ceph po/$I --force
done

if [ $? -ne 0 ] ; then
    echo "faild"
else
    echo "success"
fi
# sleep 3m
# kubectl apply -f ../storageclass.yaml
