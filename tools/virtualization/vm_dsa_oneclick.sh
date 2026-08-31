#!/usr/bin/env bash
set -euo pipefail

# One-click VM automation for node 10.239.85.54
# Includes host prep, image download, vfio passthrough, VM lifecycle, guest login checks,
# and dsa-perf-micros build in guest.

REMOTE_HOST="10.239.85.54"
REMOTE_USER="root"
REMOTE_SSH="ssh -o StrictHostKeyChecking=no ${REMOTE_USER}@${REMOTE_HOST}"
REMOTE_WORKDIR="/home/mz/vm"

VM_NAME="anolis88-vm01"
VM_PIDFILE="${REMOTE_WORKDIR}/vm-anolis88.pid"
VM_QEMU_LOG="${REMOTE_WORKDIR}/vm-anolis88-qemu.log"
VM_SERIAL_LOG="${REMOTE_WORKDIR}/vm-anolis88-serial.log"
VM_START_SH="${REMOTE_WORKDIR}/start_anolis88_vm.sh"
VM_STOP_SH="${REMOTE_WORKDIR}/stop_anolis88_vm.sh"

# Requirement-targeted passthrough device on NUMA node1
BDF="0000:0a:01.0"
BDF_SHORT="0a:01.0"
QEMU_BIN="/usr/libexec/qemu-kvm"

# Guest access through hostfwd
GUEST_SSH_PORT="2222"
GUEST_USER="root"
GUEST_PASS="123456"
GUEST_SSH="sshpass -p ${GUEST_PASS} ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no -p ${GUEST_SSH_PORT} ${GUEST_USER}@127.0.0.1"

# Image selection (current working image in environment)
BASE_IMG="AnolisOS-8.8-x86_64-RHCK.qcow2"
BASE_IMG_URL="https://mirrors.openanolis.cn/anolis/8.8/isos/GA/x86_64/${BASE_IMG}"
VM_DISK="vm-anolis88-root.qcow2"
SEED_ISO="seed-anolis88.iso"

usage() {
  cat <<EOF
Usage:
  $0 prepare     # Prepare host tools/files and generate start/stop scripts
  $0 start       # Ensure vfio binding and start VM
  $0 stop        # Stop VM
  $0 restart     # Restart VM
  $0 status      # Show VM/vfio/port status
  $0 login-test  # Test guest login (root/123456)
  $0 build       # Build /root/dsa-perf-micros inside guest
  $0 all         # prepare + restart + login-test + build

Notes:
- This script runs from your local machine and operates on ${REMOTE_HOST}.
- It depends on local ssh and sshpass.
EOF
}

require_local_tools() {
  command -v ssh >/dev/null 2>&1 || { echo "ERROR: ssh is required."; exit 1; }
  command -v sshpass >/dev/null 2>&1 || {
    echo "ERROR: sshpass is required locally. Install it first (e.g. yum install -y sshpass)."
    exit 1
  }
}

remote_prepare() {
  ${REMOTE_SSH} "bash -s" <<'EOF_REMOTE'
set -euo pipefail
REMOTE_WORKDIR="/home/mz/vm"
QEMU_BIN="/usr/libexec/qemu-kvm"
BDF="0000:0a:01.0"
BDF_SHORT="0a:01.0"
BASE_IMG="AnolisOS-8.8-x86_64-RHCK.qcow2"
BASE_IMG_URL="https://mirrors.openanolis.cn/anolis/8.8/isos/GA/x86_64/${BASE_IMG}"
VM_DISK="vm-anolis88-root.qcow2"
SEED_ISO="seed-anolis88.iso"

dnf -y install qemu-kvm qemu-kvm-core qemu-img genisoimage cloud-utils-growpart numactl pciutils sshpass || true
mkdir -p "${REMOTE_WORKDIR}"
cd "${REMOTE_WORKDIR}"

if [[ ! -f "${BASE_IMG}" ]]; then
  curl -L --fail --retry 3 -o "${BASE_IMG}" "${BASE_IMG_URL}"
fi

cat > user-data <<'EOF_USER_DATA'
#cloud-config
users:
  - name: root
    lock_passwd: false
chpasswd:
  list: |
    root:123456
  expire: false
ssh_pwauth: true
disable_root: false
write_files:
  - path: /etc/profile.d/proxy.sh
    permissions: "0644"
    owner: root:root
    content: |
      export no_proxy=127.0.0.1,localhost,.intel.com
      export https_proxy=http://proxy-dmz.intel.com:912
      export http_proxy=http://proxy-dmz.intel.com:912
runcmd:
  - [ sh, -c, "sed -ri 's/^#?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config" ]
  - [ sh, -c, "sed -ri 's/^#?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config" ]
  - [ systemctl, restart, sshd ]
EOF_USER_DATA

cat > meta-data <<'EOF_META'
instance-id: anolis88-vm01
local-hostname: anolis88-vm01
EOF_META

cat > network-config <<'EOF_NET'
version: 2
ethernets:
  eth0:
    dhcp4: true
EOF_NET

genisoimage -output "${SEED_ISO}" -volid cidata -joliet -rock user-data meta-data network-config >/tmp/geniso_vm.log 2>&1

if [[ ! -f "${VM_DISK}" ]]; then
  qemu-img create -f qcow2 -F qcow2 -b "${BASE_IMG}" "${VM_DISK}" 120G
fi

cat > start_anolis88_vm.sh <<'EOF_START'
#!/usr/bin/env bash
set -euo pipefail
cd /home/mz/vm

BDF="0000:0a:01.0"
QEMU_BIN="/usr/libexec/qemu-kvm"

modprobe -r vfio_pci || true
modprobe vfio-pci disable_denylist=1
modprobe vfio
modprobe vfio_iommu_type1

# Rebind passthrough device to vfio-pci
if [[ -e /sys/bus/pci/devices/${BDF}/driver/unbind ]]; then
  echo "${BDF}" > /sys/bus/pci/devices/${BDF}/driver/unbind || true
fi
echo vfio-pci > /sys/bus/pci/devices/${BDF}/driver_override
echo "${BDF}" > /sys/bus/pci/drivers_probe

if [[ -f vm-anolis88.pid ]] && kill -0 "$(cat vm-anolis88.pid)" 2>/dev/null; then
  echo "VM already running with PID $(cat vm-anolis88.pid)"
  exit 0
fi

numactl --cpunodebind=1 --membind=1 "${QEMU_BIN}" \
  -name anolis88-vm01 \
  -machine q35,accel=kvm \
  -cpu host \
  -smp 16,sockets=1,cores=16,threads=1 \
  -m 32768 \
  -object memory-backend-ram,id=ram0,size=32G,host-nodes=1,policy=bind \
  -numa node,nodeid=0,memdev=ram0 \
  -drive if=virtio,file=/home/mz/vm/vm-anolis88-root.qcow2,format=qcow2,cache=none,aio=native \
  -drive if=virtio,media=cdrom,file=/home/mz/vm/seed-anolis88.iso,format=raw,readonly=on \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device virtio-net-pci,netdev=net0 \
  -device vfio-pci,host=0a:01.0 \
  -display none \
  -serial file:/home/mz/vm/vm-anolis88-serial.log \
  -monitor unix:/home/mz/vm/vm-anolis88-monitor.sock,server,nowait \
  -pidfile /home/mz/vm/vm-anolis88.pid \
  -D /home/mz/vm/vm-anolis88-qemu.log \
  -daemonize

echo "VM started. PID $(cat /home/mz/vm/vm-anolis88.pid)"
EOF_START

cat > stop_anolis88_vm.sh <<'EOF_STOP'
#!/usr/bin/env bash
set -euo pipefail
cd /home/mz/vm
if [[ -f vm-anolis88.pid ]] && kill -0 "$(cat vm-anolis88.pid)" 2>/dev/null; then
  kill "$(cat vm-anolis88.pid)" || true
  sleep 2
fi
rm -f vm-anolis88.pid
EOF_STOP

chmod +x start_anolis88_vm.sh stop_anolis88_vm.sh

echo "Prepare complete in ${REMOTE_WORKDIR}"
EOF_REMOTE
}

remote_start() {
  ${REMOTE_SSH} "set -euo pipefail; cd '${REMOTE_WORKDIR}'; ./start_anolis88_vm.sh; sleep 5; ss -lntp | grep ':${GUEST_SSH_PORT}'"
}

remote_stop() {
  ${REMOTE_SSH} "set -euo pipefail; cd '${REMOTE_WORKDIR}'; ./stop_anolis88_vm.sh || true"
}

remote_status() {
  ${REMOTE_SSH} "set -euo pipefail; \
    echo '=== QEMU PROCESS ==='; ps aux | grep qemu-kvm | grep -v grep || true; \
    echo '=== PIDFILE ==='; cat '${VM_PIDFILE}' 2>/dev/null || true; \
    echo '=== SSH FORWARD ==='; ss -lntp | grep ':${GUEST_SSH_PORT}' || true; \
    echo '=== VFIO GROUP NODE ==='; ls -lah /dev/vfio/62 2>/dev/null || true; \
    echo '=== BDF DRIVER ==='; readlink -f /sys/bus/pci/devices/${BDF}/driver 2>/dev/null || true; \
    echo '=== QEMU LOG (tail) ==='; tail -n 20 '${VM_QEMU_LOG}' 2>/dev/null || true; \
    echo '=== SERIAL LOG (tail) ==='; tail -n 20 '${VM_SERIAL_LOG}' 2>/dev/null || true"
}

guest_login_test() {
  ${REMOTE_SSH} "set -euo pipefail; ${GUEST_SSH} 'echo LOGIN_OK; uname -a'"
}

guest_build() {
  ${REMOTE_SSH} "set -euo pipefail; \
    ${GUEST_SSH} 'cd /root/dsa-perf-micros && \
      export no_proxy=127.0.0.1,localhost,.intel.com && \
      export https_proxy=http://proxy-dmz.intel.com:912 && \
      export http_proxy=http://proxy-dmz.intel.com:912 && \
      dnf -y install gcc make autoconf automake libtool pkg-config || true && \
      make clean || true && \
      make -j\$(nproc) && \
      ls -lh src/dsa_perf_micros'"
}

cmd="${1:-}"
case "${cmd}" in
  prepare)
    require_local_tools
    remote_prepare
    ;;
  start)
    require_local_tools
    remote_start
    ;;
  stop)
    require_local_tools
    remote_stop
    ;;
  restart)
    require_local_tools
    remote_stop || true
    remote_start
    ;;
  status)
    require_local_tools
    remote_status
    ;;
  login-test)
    require_local_tools
    guest_login_test
    ;;
  build)
    require_local_tools
    guest_build
    ;;
  all)
    require_local_tools
    remote_prepare
    remote_stop || true
    remote_start
    guest_login_test
    guest_build
    ;;
  *)
    usage
    exit 1
    ;;
esac
