IO inbound read related event in emon parsed file, you can find below metrics and events in related sheet in xlsx file, so you can filter out the lines for these metrics and events in the xlsx.

## Metrics and events

### In `cha uncore view`, `system view` and `socket view` sheet

    metric_uncore frequency GHz
    metric_CHA RxC IRQ latency (ns)
    metric_IO_bandwidth_disk_or_network_writes (MB/sec)
    metric_IO_bandwidth_disk_or_network_reads (MB/sec)
    metric_IO_number of partial PCI writes per sec
    metric_IO read cache miss(disk/network writes) bandwidth (MB/sec)
    metric_IO_write cache miss(disk/network reads) bandwidth (MB/sec)
    metric_IO % of inbound reads that miss L3
    metric_IO bandwidth read local (MB/sec)

    UNC_CHA_CLOCKTICKS  
    UNC_CHA_RxC_INSERTS.PRQ  
    UNC_CHA_RxC_INSERTS.PRQ_REJ  
    UNC_CHA_RxC_OCCUPANCY.PRQ  
    UNC_CHA_RxC_OCCUPANCY.PRQ_REJ  
    UNC_CHA_TOR_INSERTS.IO_HIT_PCIRDCUR
    UNC_CHA_TOR_INSERTS.IO_MISS_PCIRDCUR
    UNC_CHA_TOR_INSERTS.IO_PCIRDCUR
    UNC_CHA_TOR_OCCUPANCY.IO_HIT_PCIRDCUR
    UNC_CHA_TOR_OCCUPANCY.IO_MISS_PCIRDCUR
    UNC_CHA_TOR_OCCUPANCY.IO_PCIRDCUR
    UNC_CHA_TOR_OCCUPANCY.PRQ
    UNC_CHA_PIPE_REJECT2.ANYQ_TOPA_MATCH
    UNC_CHA_TOR_INSERTS.IO_PCIRDCUR_LOCAL

### `iio uncore view` sheet

    UNC_IIO_CLOCKTICKS
    UNC_IIO_COMP_BUF_INSERTS.CMPD.ALL_PARTS
    UNC_IIO_COMP_BUF_OCCUPANCY.CMPD.ALL_PARTS
    UNC_IIO_CPL_DATAPEND_OCCUPANCY.ALL_PARTS
    UNC_IIO_COMP_BUF_INSERTS.CMPD.PART0
    UNC_IIO_COMP_BUF_INSERTS.CMPD.PART1
    UNC_IIO_COMP_BUF_INSERTS.CMPD.PART2
    UNC_IIO_COMP_BUF_INSERTS.CMPD.PART3
    UNC_IIO_COMP_BUF_INSERTS.CMPD.PART4
    UNC_IIO_COMP_BUF_INSERTS.CMPD.PART5
    UNC_IIO_COMP_BUF_INSERTS.CMPD.PART6
    UNC_IIO_COMP_BUF_INSERTS.CMPD.PART7
    UNC_IIO_COMP_BUF_INSERTS.CMPD.ALL_PARTS
    UNC_IIO_NUM_OUSTANDING_REQ_FROM_CPU.TO_IO
    UNC_IIO_COMP_BUF_OCCUPANCY.CMPD.PART0
    UNC_IIO_COMP_BUF_OCCUPANCY.CMPD.PART1
    UNC_IIO_COMP_BUF_OCCUPANCY.CMPD.PART2
    UNC_IIO_COMP_BUF_OCCUPANCY.CMPD.PART3
    UNC_IIO_COMP_BUF_OCCUPANCY.CMPD.PART4
    UNC_IIO_COMP_BUF_OCCUPANCY.CMPD.PART5
    UNC_IIO_COMP_BUF_OCCUPANCY.CMPD.PART6
    UNC_IIO_COMP_BUF_OCCUPANCY.CMPD.PART7
    UNC_IIO_COMP_BUF_OCCUPANCY.CMPD.ALL_PARTS

### In the `core view` and `thread view` and `system view` and `socket view` sheet
    
    metric_CPU operating frequency (in GHz)
    metric_UPI speed - GT/s
    metric_CPU utilization %
    metric_CPU utilization% in kernel mode
    metric_CPI
    metric_kernel_CPI
    metric_core IPC


### TMA related events in the `core view` and `thread view` and `system view` and `socket view` sheet
 - please refer to [emon_TMA](emon_TMA.md)