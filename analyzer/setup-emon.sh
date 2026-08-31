#!/bin/bash

emon_bin_path="/usr/local/emon"

if [ ! -e $emon_bin_path/sep/sep_vars.sh ]; then
    yum install -y curl python3-pip bzip2 gcc
    curl --retry 5 -o - https://af01p-igk.devtools.intel.com/artifactory/platform_hero-repos/emon/11_36_private/sep_private_5_36_linux_09132207f3c71f9.tar.bz2 | tar xfj - -C /usr/local/src

    [ -d /usr/src/kernels/$(uname -r) ] || yum install -y "@Development Tools" kernel-devel-$(uname -r) || yum install -y "@Development Tools" kernel-devel
    grep -q -E '^vtune:' /etc/group || groupadd vtune
    mkdir -p $emon_bin_path
    (
        cd /usr/local/src/sep_*
        ./sep-installer.sh -u -C $emon_bin_path --accept-license -ni -i -g vtune --c-compiler $(which gcc)
    )
    python3 -m pip install --no-cache-dir pandas numpy defusedxml pytz tdigest xlsxwriter
fi
