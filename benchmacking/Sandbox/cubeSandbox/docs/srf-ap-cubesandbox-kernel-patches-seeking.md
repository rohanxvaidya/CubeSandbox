### description

This is the guide to test the cubesandbox performance for create-delete case on SRF-AP platform with differnet kernel version. 
This file is to find the related kernel patches that impact the cubesandbox benchmark performance on target remote server. I have verified that the patches are in kernel `v6.17`, since the cubesandbox benchmark performance is good (for concurrency is less than 200, avg latency is < 200 ms), and the patches are not in kernel `v6.16`, becuase with kernel `6.16` the performance is bad(much large than 200 ms when cubesandbox concurrency is 200).
Based on the kernel verson `6.16.0`, to find the patches between v6.15.0 and v6.16.0 that impact the performance, you can switch to specific commit ID between these two versions, and build, install the kernel, and reboot system, then wait to system bootup and enter the system to verify the performance.
你可以使用二分法的方式持续验证kernel的commit，找到对应的commits。
You can continously do it until you find the patches that improve the performance.(latency less than 200ms)

And I suspect that the pacthes impact the performace is scheduler realted in the kernel, just for your reference.
### remote target server SRF-AP
- Node IP: `10.239.23.60`, you can access it with `ssh -l root 10.239.23.60`


### kernel code and build:
- kernel Source code: in remote SRF node, `/home/mz/kernel/linux-srf` , it's the `git` based source code, and you can switch to v6.16 or previous version branch/tag.
- You can change the kernel build version in Makefile.
- You can build and install the kernel with this commands:
```
cp /home/mz/kernel/config-6.6.0-srf.bkc.6.6.29.4.32.x86_64 .config
scripts/config --disable SYSTEM_TRUSTED_KEYS
scripts/config --disable SYSTEM_REVOCATION_KEYS 
make olddefconfig
make -j200 && make modules -j200 && make INSTALL_MOD_STRIP=1  modules_install -j200 && make install
```
- After build the kernel, you can set the boot kernel with this command, then to reboot, for example, swith kernel version to 6.16.0
```Boot with a real installed kernel version string
sudo /usr/local/sbin/kernel-default 6.16.0
```
- And please note that the `/boot` capacity pressure before you build new kernel(check `/boot` remain capacity before build kernel, at least keep 200M before build). you can backup the old kernel files from /boot to `/home/mz/kernel/backup/` when there is no enouth capacity in `/boot` folder

Important:
- `kernel-default` must match an installed kernel version string. If version does not exist, it returns `Kernel not found`.
- You can check available kernels with:
```
ls -1 /boot/vmlinuz*
grubby --info=ALL | egrep "^index=|^kernel="
```
- After reboot, always verify:
```
uname -r
```

- You have permission to reboot the remote system after swap the kernel.After trige the reboot, wait 5 minutes, then you can enter the system to verify the kernel version and benchmark;

### How to test.
1. Create a new teamplate with following command, you can get a new template_id to run test, or you use the template `tpl-3cbb2ac9d8054411af13cb74` in system.
```
cubemastercli -a 127.0.0.1 tpl create-from-image   --image cube-sandbox-cn.tencentcloudcr.com/cube-sandbox/sandbox-code:latest   --writable-layer-size 1G   --expose-port 49999   --expose-port 49983   --probe 49999  --probe-path /health 
sleep 10s
```

2. Run the cubesandbox benchmark with following command, and check the result in `/tmp/cube.json`, you can check the benchmark script for the benchmark details. And please note that, you should check the cubesandbox services are ready before start the benchmark;
```
bash /home/mz/cubeSandbox/quick_bench_cube.sh template_id
```

or you can run the test directly:
```
bash /home/mz/cubeSandbox/quick_bench_cube.sh template_id
```

We only check the `create` case performnace, and record the performance for each round test.
- "success_rate", it's better `1`, large than `0.9` is also OK.
- "avg" latency, it should be < 200, (you can run this benchmark 5 time, record all of the avg latency, and get the average value for this)

### permission on this remote SRF-AP node
You have any permission on this remote server, don't ask me for permisssion for operation on this remote server.

## insight
		-- for new kernel 6.17, tempalte id = tpl-0c5aa522238c4b059999d6fe , 260-280 concurrency, the avg create latency is 200ms, and 200 concurrency i will be ~160ms, less than 200ms. 
		-- for new kernle 6.15, need to create a new template id = tpl-14fee78796424a209f04f51d  --> 155 ~160 concurrency, avg create latency is ~200ms~220ms
		-- for new kernel 6.16, use template id = tpl-14fee78796424a209f04f51d /tpl-3cbb2ac9d8054411af13cb74 --> 155 ~160 concurrency, avg create latency is ~200ms~220ms