app: pcimem.c

build it, or you can directly use the ELF file applicaton: [pcimem](pcimem). 
```
gcc -o pcimem pcimem.c  
```
Note: If memory access strict config is enabled in your system kernel, you can take one of options to disable the strict: 1, add kernell parameter in boot cmdline `iomem=relaxed`; OR 2,build kernel by disable `CONFIG_IO_STRICT_DEVMEM`.

1, map the MMIO range to uncachable  
 a, find the MMIO base address for the pci device: 
```
  e.g.  lspci -s 0000:45:00.0 -vv | grep Region , you can get 0x213ffc000000  
```
 b, set the address to uncachable:  
``` 
  e.g. echo "base=0x213ffc000000 size=0x1000000 type=uncachable" >  /proc/mtrr
  note: if this address is alread mapped with uncachable by kernel driver, user can ignore this step.
```

2, test the mmio address with app  
```
./pcimem -h
Usage: ./pcimem -m <pci|memio> -b <bdf|bar_base_hex> -s <bar_size_hex> -o <r|w> -r <reg_offset_hex> [-v <value>] [other options]
Options: (V1.1)
  -m <pci|memio>      Specify the mode of operation.
  -b <bdf|bar_base>   Specify BDF for PCI or BAR base address for MMIO. (e.g.3e:00.0 for pci mode or 0x80000000 for mmio)
  -s <bar_size_hex>   Specify the size of the BAR in hexadecimal.
  -o <r|w|m>          Specify the operation: read (r) or write (w) or mixed r/w (m).
  -r <reg_offset_hex> Specify the register offset in hexadecimal.
  -v <value>          Specify the value to write (required for write operations).
  -l <count>          Specify the loop count to read/write operations.
  -w <0|1|2|3|4>      Add certain instruction after MMIO write, by default is serialize (1),
                        0 - no instruction after MMIO ops,
                        1 - With serialize instruction after MMIO ops,
                        2 - With LOCK# instruction after MMIO ops,
                        3 - With PAUSE instruction after MMIO ops,
                        4 - With mFENCE instruction after MMIO ops,
  -M <0|1|2>          Ouput messsage mode, by default is full message (2),
                        0 - Quiet mode for MMIO ops, no message output
                        1 - Simple message mode for MMIO ops,
                        2 - Full message mode for MMIO ops,
  -c <write_ops>      Specify the count for Write ops for each cycle test, default is 4
  -h                  Show help usage.
```

### example:  
use memio mode to access MMIO address 0x213ffc080000, map range size 0x1000, 
and do read operation on register offset 0x00, will loop the operation 2 times. 
```
./pcimem -m memio -b 0x213ffc080000 -s 0x1000 -o r -r 0x00 -l 2 
```

## Simulate Stress  
  simulate stress similar with the NIC MMIO issue on redis workload
  Run the script mmio stress.sh in current folde, with parameters.
```  
  e.g. base_addr=0x1e5ffa080000 bash mmio_stress.sh 6 1000000  
```
  --> 6 threads on 6 core,c0-c5, with 1000000 loop count for each thread. operation MMIO write on address 0x1e5ffa080000, which is mapped to PCIe device.
  Then check the TSC duration for each MMIO read/write in log file in folder log/. 

#### thread scaling for stress test
  Run the script mmio stress.sh in current folde, with parameters.
```  
  e.g. base_addr=0x1e5ffa080000 bash mmio_stress.sh 10 1000000 1
```
  --> This will test the mmio stress with 1000000 loop, and enable the thread scaling from 1 to 10.  