## Description
This is a memcopy latency test tool, which support DSA and CPU use case. This tool initially comes from the CSP PolarStor's IO thrad scenarios that use DSA or CPU to implement memory copy to CXL memory;
And this tools also support memocy copy from/to DRAM.
At the begining, we use this tool to simulate & reproduce the DSA random-spike-latency issue [`IPS`](https://hsdes.intel.com/appstore/article-one/#/article/14026863678) and [`Sighting`](https://hsdes.intel.com/resource/15018939498) , there are several spike latency(>600us) within 1 Million operation to DSA with shared WQ.

### Configuration:
1, Ensure that at least one DSA devcie is enabled in your server, and the idxd driver is loaded, generally it's by default;  
2, Ensure IOMMU is enabled in your server, `cat /proc/cmdline`, otherwise, you need to add `intel_iommu=on,sm_on iommu=pt` in your grub.cfg;  
3, Ensure the `accel-config` tool and library is installed, by default, it's installed, otherwise you can install with `yum install` or `apt-get install`, or build with code from github;  
4, At least enable one sharedWQ on a DSA device, and suggest to enable the BOF function;   
 -- please refer to [`check.sh`] (check.sh) to enable the sharedWQ;

##### Simulate the DSA spike latency issue with shared WQ
Based on numa node0 memory, and with clx device /dev/dax8.0, on cpu 16. -w write to dax device with DSA wq0.0.   
only show large than 150us latency operations. and test with light mode with 1 operation and 1x 20 us waiting   
```
numactl -m 0 ./dsa_memcpy_latency -d /dev/dax8.0 -b 16384 -s 1073741824 -i 10000000 -k 16 -w -q /dev/dsa/wq0.0 -o 1 -D 0 -I 1 -S 20 -C 0 -T 150000 -L 1 -g 1 -P -W 1 -I 1
```
Enable dedicated wq and enable verify data for test   
```
numactl -m 0 ./dsa_memcpy_latency -d /dev/dax8.0 -b 16384 -s 1073741824 -i 10000000 -k 16 -w -q /dev/dsa/wq0.0 -o 1 -D 0 -I 1 -S 20 -C 0 -T 150000 -L 1 -g 1 -P -W 1 -I 1 -Q -v
```

## Use this tool
1, Build this tool:
 Please ensure the lib-accel-config, libpmem and libnuma* are installed.
```
gcc dsa_memcpy_latency.cpp -o dsa_memcpy_latency -lpmem
```
 Or if accel-config libary is installed in specific directory. you can specify the link path:  
``` 
gcc dsa_memcpy_latency.cpp -o dsa_memcpy_latency -l accel-config -I /usr/include -lpmem
```
1a, For libary depends, for example:
```
  For centos related OS: yum install libnuma* numa* libpmem* -y
```

2, How to use this tool 
```
./dsa_memcpy_latency -h
    Options: (V1.4). This tool is used for testing dsa memmove latency
    [-a x, Calculate the average latency for x operations]
    [-d dax device path]
    [-N x, NUMA node for memory test ]
    [-s dax device size]
    [-b memcpy block size]
    [-f pre-fill data with memset for buffers, 0- not fille, 1- prefill]
    [-F Use the fence instruction before DSA operation]
    [-i memcpy iteration number]
    [-k bind cpu num]
    [-w write from local memory to device, otherwise read]
    [-m use local memory as write/read destination, otherwise it will use dax device on CXL device]
    [-q dsa wq path, e.g. /dev/dsa/wq0.0]
    [-o iodepth, defined request depth in each operaton iteration]
    [-C memcpy operator: 0-DSA; 1-CPU glibc memcpy; 2-CPU libpmem, NT store; ]
    [-D Data Model for operation; 0- 4k header + 16k header; 1 - only 4k header; 2 - only 16k data]
    [-I usleep interval, i.e. -I 10, then compete 10 ops, will have x us sleep]
    [-T print threshold (ns), only print the latency large than this threshold]
    [-S sleep time(us) between two OPs]
    [-F Enable fence before submit; bydefault it's disabled. Enable it if BOF is enabled.]
    [-g debug mode, 0-logging whole ops; 1-logging each phase; 2- log more; bydefault 0]
    [-P Enable DSA WQ portal address increase (switch with round robin in 4k)]
    [-W Wait function, 0: usleep or 1: busy loop. bydefault is 0;]
    [-v Enable verify data after memcopy]
    [-t Set the timestamp method, 0-sys time api; 1-rdtsc]
    [-O Ordering flag, 0- relaxed ordering; 1- Strict ordering; bydefault it's 0]
    [-Z Post fence after memcopy, 0-NON fence; 1-sfence;2-mfence]
    [-X <r|w|m> Test with single IO mode, specify the operation: read (r) or write (w) or mixed r/w (m).]
                *** for Single IO test mode ***
            [-l loop_count, Test with single IO mode, specify loop count for read/write]
            [-r reg_offset, Test with single IO mode, specify register offset on based address]
            [-V value, Test with single IO mode, specify write value]
```

### Contribution:
 : [`Michael.M.Zhang`](Michael.M.Zhang@intel.com)
 : [`Guoqing Meng`](guoqing.meng@intel.com)
 : [`Jiejie Liu`](jiejie.liu@intel.com)