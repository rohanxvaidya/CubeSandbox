#accel-config disable-device iax
#rmmod iaa_crypto
#rmmod idxd
#echo 1 > /sys/bus/pci/devices/0000:00:01.0/reset
#modprobe idxd

cxl monitor --daemon --log=/var/log/cxl-monitor.log

/home/mz/dsa-perf-micros/scripts/setup_dsa.sh -d dsa0 -w 1 -m s -e 1

cat /sys/bus/dsa/devices/dsa*/state
