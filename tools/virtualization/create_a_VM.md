## Description:
This md is used for create a qemu virtual machine on a specified server node;

please create a qemu VM on the target node, and pass throught some pcie device to VM, refer to these requirment as below:
 -  Target server node access : `root@10.239.85.54` , you can access without password;
 -  Work directory in target node: `/home/mz/vm/`, you can write/modify in this folder, and store all of the tools/config files/OS image in this work space.
 -  Qemu version: you can use the latest stable version, or the stable version you know, it's better to use latest stable version;
 -  Guest OS: Anolis OS 8.* (maybe 8.8), with the kernel 5.10.134-* , you should find it in internet.
 -  Guest OS acount: `root`, password:`********`;
 -  Guest OS IP: use the hots IP, and the ssh port is `2222`;
 -  Binding core and memory: please bind to numa node1
 -  For the Guest network, please ensure it can access external network to download tools/rpm, or yum install packages;
 -  In Guest, it may need add proxy for network to access external network: please use below proxy if needed:
 -  Pass through device: please find out with `lspci`, the device name is `Intel Corporation Device 0b25`

 ``` Network proxy in Guest
no_proxy=127.0.0.1,localhost,.intel.com
https_proxy=http://proxy-dmz.intel.com:912
http_proxy=http://proxy-dmz.intel.com:912
 ```


## Permission:
You can install any tools without asking permission;
You can modify in the Work directory in target node: `/home/mz/vm/`

## tools:
please save all the scripts you used in this folder along with this md file;