### description

This is the guide to test the cubesandbox performance for create-delete case on SRF-AP platform with differnet kernel version. 
This file is to find the related kernel patches that impact the cubesandbox benchmark performance on target remote server CWF. I have verified that the patches are in kernel v6.8, since the cubesandbox benchmark performance is good (avg latency is < 200 ms), and the patches are not in kernel v6.7, becuase with kernel 6.7 the performance is bad(much large than 200 ms, e.g. around 240ms).
Based on the kernel verson 6.7.0, to find the patches between v6.7.0 and v6.8.0 that impact the performance, you can switch to specific commit ID between these two versions, and build, install the kernel, and reboot system, then wait to system bootup and enter the system to verify the performance.
你可以使用二分法的方式持续验证kernel的commit，找到对应的commits。
You can continously do it until you find the patches that improve the performance.(latency less than 200ms)

And I suspect that the pacthes impact the performace is scheduler realted in the kernel, just for your reference.
### remote target server SRF-AP
- Node IP: `10.239.23.60`, you can access it with `ssh -l root 10.239.23.60`


### kernel code and build:
- kernel Source code: in remote CWF node, `/home/mz/kernel/linux/` , it's the `git` based source code, and you can switch to v6.18 or previous version branch/tag.
- You can change the kernel build version in Makefile.
- You can build and install the kernel with this commands:
```
make -j200 && make modules -j200 && make INSTALL_MOD_STRIP=1  modules_install -j200 && make install
```
- After build the kernel, you can set the boot kernel with this command, then to reboot
```Boot with a real installed kernel version string
sudo /usr/local/sbin/kernel-default 6.7.0
```
- And please note that the `/boot` capacity pressure before you build new kernel. you can backup the old kernel files from /boot to `/home/mz/kernel/backup/`

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

- After trige the reboot, wait 5 minutes, then you can enter the system to verify the kernel version and benchmark;

### How to test.
1. Create a new teamplate with following command, you can get a new template_id to run test.
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





### reference

kernel_version,rounds_total,rounds_ok,success_rate_mean,create_avg_ms_mean,pass_success_rate,pass_create_avg,overall_pass
6.6.0,5,0,0.0,0.0,0,0,0
6.7.0,5,5,1.0,240.0,1,1,1
6.8.0,5,5,1.0,106.29628759999999,1,1,1
6.9.0,5,5,1.0,98.358282,1,1,1
6.10.0,5,5,1.0,104.47001720000003,1,1,1
6.11.0,5,5,1.0,101.94603399999995,1,1,1
6.12.0,5,5,1.0,93.77365600000003,1,1,1
6.13.0,5,5,1.0,94.71495759999996,1,1,1


kernel_release,run_id,template_id,create_avg_ms,create_p95_ms,create_p99_ms,success_rate,errors,total_time_s,note
6.14.0,1,tpl-5c34865471d94aed81c21a50,121.73804800000005,260.353,275.95,1,0,1.859935406,ok
6.14.0,2,tpl-5c34865471d94aed81c21a50,110.03653200000002,179.656,195.947,1,0,1.8860440120000002,ok
6.14.0,3,tpl-5c34865471d94aed81c21a50,114.8730279999999,194.437,211.044,1,0,1.920093499,ok
6.14.0,4,tpl-5c34865471d94aed81c21a50,116.78100199999999,202.785,213.256,1,0,1.900974913,ok
6.14.0,5,tpl-5c34865471d94aed81c21a50,110.13376399999999,208.513,219.749,1,0,1.834287728,ok
6.15.0,1,tpl-5c34865471d94aed81c21a50,118.39730399999993,229.739,242.975,1,0,1.931704425,ok
6.15.0,2,tpl-5c34865471d94aed81c21a50,112.50583599999995,204.887,216.444,1,0,1.871083217,ok
6.15.0,3,tpl-5c34865471d94aed81c21a50,110.40721200000006,196.39,214.263,1,0,1.807317624,ok
6.15.0,4,tpl-5c34865471d94aed81c21a50,109.26840399999993,193.28,236.937,1,0,1.8277964020000002,ok
6.15.0,5,tpl-5c34865471d94aed81c21a50,117.86990200000004,206.234,217.122,1,0,1.879759287,ok
6.16.0,1,tpl-5c34865471d94aed81c21a50,118.19705400000002,247.883,261.336,1,0,1.8836138070000001,ok
6.16.0,2,tpl-5c34865471d94aed81c21a50,114.133468,203.718,233.679,1,0,1.8259229449999999,ok
6.16.0,3,tpl-5c34865471d94aed81c21a50,112.6543,202.392,215.188,1,0,1.877551653,ok
6.16.0,4,tpl-5c34865471d94aed81c21a50,109.46588199999995,207.199,230.1,1,0,1.7927089459999999,ok
6.16.0,5,tpl-5c34865471d94aed81c21a50,107.33511400000002,202.372,226.636,1,0,1.8205239,ok
6.17.0,1,tpl-5c34865471d94aed81c21a50,99.95268799999997,166.052,193.233,1,0,1.722209586,ok
6.17.0,2,tpl-5c34865471d94aed81c21a50,95.01314800000002,141.446,155.147,1,0,1.7118558670000001,ok
6.17.0,3,tpl-5c34865471d94aed81c21a50,92.79438799999998,136.168,148.263,1,0,1.734626795,ok
6.17.0,4,tpl-5c34865471d94aed81c21a50,91.61321399999989,139.64,156.941,1,0,1.712712442,ok
6.17.0,5,tpl-5c34865471d94aed81c21a50,86.78599599999997,147.516,160.618,1,0,1.611551636,ok
6.18.0,1,tpl-5c34865471d94aed81c21a50,104.8214560000001,174.177,196.458,1,0,1.775640692,ok
6.18.0,2,tpl-5c34865471d94aed81c21a50,87.14776000000008,151.454,160.878,1,0,1.569580465,ok
6.18.0,3,tpl-5c34865471d94aed81c21a50,96.31795400000001,139.724,151.581,1,0,1.7015552330000001,ok
6.18.0,4,tpl-5c34865471d94aed81c21a50,87.92243799999984,125.503,135.195,1,0,1.6033376289999999,ok
6.18.0,5,tpl-5c34865471d94aed81c21a50,91.75856000000009,141.772,150.544,1,0,1.670377636,ok


##### table:
Updated todo list

Read [](file:///root/Mydata-SPRinspur22/0_work/9x_new_work/9_workloads/cubesandbox/cubesandbox_kernel_patches_srf-ap.md)

以下是对两段数据的整理：

---

### 表一：各内核版本汇总测试结果（6.6 ~ 6.13）

| kernel_version | rounds_total | rounds_ok | success_rate | create_avg_ms | pass_success_rate | pass_create_avg | overall_pass |
|:--------------:|:------------:|:---------:|:------------:|:-------------:|:-----------------:|:---------------:|:------------:|
| 6.6.0  | 5 | 0 | 0.0  | —       | 0 | 0 | ❌ |
| 6.7.0  | 5 | 5 | 1.0  | 240.00  | 1 | 1 | ⚠️ (慢) |
| 6.8.0  | 5 | 5 | 1.0  | 106.30  | 1 | 1 | ✅ |
| 6.9.0  | 5 | 5 | 1.0  | 98.36   | 1 | 1 | ✅ |
| 6.10.0 | 5 | 5 | 1.0  | 104.47  | 1 | 1 | ✅ |
| 6.11.0 | 5 | 5 | 1.0  | 101.95  | 1 | 1 | ✅ |
| 6.12.0 | 5 | 5 | 1.0  | 93.77   | 1 | 1 | ✅ |
| 6.13.0 | 5 | 5 | 1.0  | 94.71   | 1 | 1 | ✅ |

---

### 表二：各轮次详细测试数据（6.14 ~ 6.18）

| kernel | run | create_avg (ms) | create_p95 (ms) | create_p99 (ms) | success_rate | errors | total_time (s) |
|:------:|:---:|:---------------:|:---------------:|:---------------:|:------------:|:------:|:--------------:|
| 6.14.0 | 1 | 121.74 | 260.35 | 275.95 | 1 | 0 | 1.860 |
| 6.14.0 | 2 | 110.04 | 179.66 | 195.95 | 1 | 0 | 1.886 |
| 6.14.0 | 3 | 114.87 | 194.44 | 211.04 | 1 | 0 | 1.920 |
| 6.14.0 | 4 | 116.78 | 202.79 | 213.26 | 1 | 0 | 1.901 |
| 6.14.0 | 5 | 110.13 | 208.51 | 219.75 | 1 | 0 | 1.834 |
| **6.14 avg** | — | **114.71** | — | — | — | — | — |
| 6.15.0 | 1 | 118.40 | 229.74 | 242.98 | 1 | 0 | 1.932 |
| 6.15.0 | 2 | 112.51 | 204.89 | 216.44 | 1 | 0 | 1.871 |
| 6.15.0 | 3 | 110.41 | 196.39 | 214.26 | 1 | 0 | 1.807 |
| 6.15.0 | 4 | 109.27 | 193.28 | 236.94 | 1 | 0 | 1.828 |
| 6.15.0 | 5 | 117.87 | 206.23 | 217.12 | 1 | 0 | 1.880 |
| **6.15 avg** | — | **113.69** | — | — | — | — | — |
| 6.16.0 | 1 | 118.20 | 247.88 | 261.34 | 1 | 0 | 1.884 |
| 6.16.0 | 2 | 114.13 | 203.72 | 233.68 | 1 | 0 | 1.826 |
| 6.16.0 | 3 | 112.65 | 202.39 | 215.19 | 1 | 0 | 1.878 |
| 6.16.0 | 4 | 109.47 | 207.20 | 230.10 | 1 | 0 | 1.793 |
| 6.16.0 | 5 | 107.34 | 202.37 | 226.64 | 1 | 0 | 1.821 |
| **6.16 avg** | — | **112.36** | — | — | — | — | — |
| 6.17.0 | 1 | 99.95 | 166.05 | 193.23 | 1 | 0 | 1.722 |
| 6.17.0 | 2 | 95.01 | 141.45 | 155.15 | 1 | 0 | 1.712 |
| 6.17.0 | 3 | 92.79 | 136.17 | 148.26 | 1 | 0 | 1.735 |
| 6.17.0 | 4 | 91.61 | 139.64 | 156.94 | 1 | 0 | 1.713 |
| 6.17.0 | 5 | 86.79 | 147.52 | 160.62 | 1 | 0 | 1.612 |
| **6.17 avg** | — | **93.23** | — | — | — | — | — |
| 6.18.0 | 1 | 104.82 | 174.18 | 196.46 | 1 | 0 | 1.776 |
| 6.18.0 | 2 | 87.15 | 151.45 | 160.88 | 1 | 0 | 1.570 |
| 6.18.0 | 3 | 96.32 | 139.72 | 151.58 | 1 | 0 | 1.702 |
| 6.18.0 | 4 | 87.92 | 125.50 | 135.20 | 1 | 0 | 1.603 |
| 6.18.0 | 5 | 91.76 | 141.77 | 150.54 | 1 | 0 | 1.670 |
| **6.18 avg** | — | **93.59** | — | — | — | — | — |


### analysis and result

当前结论：

用正确语义做的 first-parent bisect 已经收敛
找到的 first fast commit 是：
3e7aeb78ab01c2c2f0e1f784e5ddec88fcd3d106
提交标题：
Merge tag 'net-next-6.8' of git://git.kernel.org/pub/scm/linux/kernel/git/netdev/net-next
这表示什么：

性能从 v6.7 的慢 到 <200ms 的快，边界已经收敛到这个 first-parent 合并点
也就是说，性能提升出现在 net-next-6.8 这批补丁里
这和最开始“可能是 scheduler” 的猜测不一致；目前证据更偏向 network / net-next 方向
关键 bisect 路径：

32720aca900b → slow
42bff4d0f9b9 → fast
5bad490858c3 → fast
acc657692aed → slow
a05aea98d405 → slow
c29901006179 → slow
de927f6c0b07 → slow
3e7aeb78ab01 → first fast
当前远端状态：

当前运行内核：6.7.0-02723-gde927f6c0b07
这是最后测试到的一个 slow 点，不是最终边界 commit 本身
日志位置：

主日志：/root/Mydata-SPRinspur22/0_work/9x_new_work/9_workloads/cubesandbox/bisect_fast_boundary_20260805_235118.log
CSV：/root/Mydata-SPRinspur22/0_work/9x_new_work/9_workloads/cubesandbox/bisect_fast_boundary_20260805_235118.csv


如果你要做手动对比测试，最应该选这两个：

角色	kernel git commit	说明
slow 对照点	de927f6c0b07d9e698416c5b287c521b07694cac	bisect 里确认是 slow
fast 对照点	3e7aeb78ab01c2c2f0e1f784e5ddec88fcd3d106	bisect 收敛出的 first fast commit
也就是直接测这两个相邻边界点：

before: de927f6c0b07 → 慢
after: 3e7aeb78ab01 → 快
如果你想做一个更大差异的 sanity check，也可以额外测：

0dd3ee31125508cd67f7e7172247f05b7fd1753a = v6.7
3e7aeb78ab01c2c2f0e1f784e5ddec88fcd3d106 = first fast
但要定位“哪一批 patch 导致提升”，首选还是 de927f6c0b07 对 3e7aeb78ab01。



原因很简单：

3e7aeb78ab01... 是一个 merge commit
它的 第一父提交 是
de927f6c0b07d9e698416c5b287c521b07694cac
它的 第二父提交 是
a7fe0881d9b78d402bbd9067dd4503a57c57a1d9（net-next-6.8 分支头）
而我刚核对过：

60a031b64984ad4a219a13b0fe912746b586bb9b
不是 3e7aeb... 的父提交
它也 不在 60a031..3e7aeb 的 ancestry path 上
所以如果你是想做**“merge 前 vs merge 后”的手动对比**，正确的两点是：

角色	commit
merge 前（slow）	de927f6c0b07d9e698416c5b287c521b07694cac
merge 后（fast）	3e7aeb78ab01c2c2f0e1f784e5ddec88fcd3d106
如果你想进一步细化到 net-next-6.8 合并里到底哪一个 patch，那下一层应该围绕 第二父分支 去追：

merge base / 主线侧：de927f6...
net-next 分支头：a7fe0881d9b7...
然后在 net-next 这条分支内部继续找，不是拿 60a031... 这种“日志上一条”来比。