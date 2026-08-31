#!/bin/bash
#

MOD_NAME=${MOD_NAME:-"spinlock_bench"}

IN_TREE_DIR=/lib/modules/`uname -r`/kernel/spinlock_bench

mkdir -p $IN_TREE_DIR
cp $MOD_NAME.* modules.order Module.symvers  $IN_TREE_DIR

depmod -a