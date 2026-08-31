#!/bin/bash

BASE_PATH=/opt
WORK_PATH=${BASE_PATH}/kernel
LOG_PATH=${BASE_PATH}/logs

cd ${WORK_PATH}/
## prepare the .config file. and run make menuconfig to check again.

#vim .config
scripts/config --disable SYSTEM_TRUSTED_KEYS
scripts/config --disable SYSTEM_REVOCATION_KEYS
# apt install zstd
make -j128
make moudles -j128
make modules_install
make install