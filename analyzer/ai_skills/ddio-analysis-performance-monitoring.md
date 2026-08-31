# Introduction to Intel(R) Data Direct I/O Technology (Intel(R) DDIO) Analysis with Performance Monitoring

Source: https://www.intel.com/content/www/us/en/developer/articles/technical/ddio-analysis-performance-monitoring.html
Published: August 2, 2024

## 1 Introduction

Intel(R) DDIO enables I/O devices (NICs, storage controllers, and other peripherals) to access CPU LLC directly, improving latency, bandwidth, and CPU efficiency.

Key points:
- Intel(R) DDIO is transparent to software.
- PerfMon is required to observe how effectively DDIO is being used.
- Focus of the article is 4th/5th Gen Intel(R) Xeon(R) Scalable Processors (SPR/EMR), though concepts apply more broadly.

## 2 Architecture Background

### 2.1 Platform Overview

Main uncore components discussed:
- Core (L1/L2 caches)
- CHA/LLC (coherency + LLC slices, key DDIO observability point)
- M2IOSF (IIO/IRP/M2PCIE bridge between mesh and PCIe/CXL)
- IMC (memory controller)
- UPI (socket interconnect)

### 2.2 Intel(R) DDIO Transaction Overview

DDIO behavior summarized for inbound I/O:
- Inbound writes: ownership phase + writeback phase
- Inbound reads: can hit LLC or miss and fetch elsewhere (other caches, memory)
- Requests are coherent and handled by CHA/TOR mechanisms
- Writes can be allocating (default) or non-allocating

Important concepts:
- LLC hit vs LLC miss on inbound traffic
- Partial vs full cache-line transactions
- IO_LLC_WAYS controls LLC ways available to inbound I/O write allocations

### 2.3 Performance Monitoring Overview

PerfMon event definitions and metrics are published in Intel perfmon JSON repositories:
- https://github.com/intel/perfmon/

Naming conventions in uncore events help identify the counting unit, e.g.:
- CHA, M2IOSF (IIO/IRP), M2M, M2P, UPI, IMC

IIO `.PART[0-7]` events map traffic to PCIe bifurcation parts (up to x4 granularity).

## 3 Observing Intel(R) DDIO with PerfMon

### 3.1 CHA PerfMon

CHA TOR insert events are central to DDIO effectiveness analysis.

Representative events:
- UNC_CHA_TOR_INSERTS.IO_PCIRDCUR
- UNC_CHA_TOR_INSERTS.IO_HIT_PCIRDCUR
- UNC_CHA_TOR_INSERTS.IO_MISS_PCIRDCUR
- UNC_CHA_TOR_INSERTS.IO_ITOM
- UNC_CHA_TOR_INSERTS.IO_HIT_ITOM
- UNC_CHA_TOR_INSERTS.IO_MISS_ITOM
- UNC_CHA_TOR_INSERTS.IO_ITOMCACHENEAR
- UNC_CHA_TOR_INSERTS.IO_HIT_ITOMCACHENEAR
- UNC_CHA_TOR_INSERTS.IO_MISS_ITOMCACHENEAR
- UNC_CHA_TOR_INSERTS.IO_WBMTOI
- UNC_CHA_TOR_INSERTS.IO_CLFLUSH

Representative metrics:
- io_percent_of_inbound_reads_that_miss_l3
- io_percent_of_inbound_full_writes_that_miss_l3
- io_percent_of_inbound_partial_writes_that_miss_l3

### 3.2 M2IOSF / IIO PerfMon

IIO provides per-device/per-part observability and finer data granularity.

Representative events:
- UNC_IIO_TXN_REQ_OF_CPU.MEM_WRITE.PART[0-7]
- UNC_IIO_TXN_REQ_OF_CPU.MEM_READ.PART[0-7]
- UNC_IIO_TXN_REQ_OF_CPU.CMPD.PART[0-7]
- UNC_IIO_TXN_REQ_BY_CPU.MEM_WRITE.PART[0-7]
- UNC_IIO_TXN_REQ_BY_CPU.MEM_READ.PART[0-7]
- UNC_IIO_DATA_REQ_OF_CPU.MEM_WRITE.PART[0-7]
- UNC_IIO_DATA_REQ_OF_CPU.MEM_READ.PART[0-7]
- UNC_IIO_DATA_REQ_OF_CPU.CMPD.PART[0-7]
- UNC_IIO_DATA_REQ_BY_CPU.MEM_WRITE.PART[0-7]

Representative metrics:
- io_inbound_read_requests
- io_inbound_read_bandwidth
- io_inbound_write_requests
- io_inbound_write_bandwidth
- io_outbound_read_requests
- io_outbound_read_bandwidth
- io_outbound_write_requests
- io_outbound_write_bandwidth

### 3.3 IMC PerfMon

DDR demand monitoring uses:
- UNC_M_CAS_COUNT.RD
- UNC_M_CAS_COUNT.WR

Memory bandwidth metrics:
- memory_bandwidth_read
- memory_bandwidth_write
- memory_bandwidth_total

### 3.4 Flow Decoder

Article maps events to inbound and outbound I/O flow diagrams and explains why some completion data appears under specific event families.

## 4 Workload Optimizations to Improve DDIO Efficiency

Optimization suggestions from the article:
- Reuse memory addresses for I/O buffers
- Improve temporal locality
- Reduce time-to-use of inbound data
- Reduce application working set
- Increase I/O LLC ways

## 5 Example Analysis (iperf3)

Case study summary:
- Reducing queue size improved DDIO effectiveness and throughput (~16% gain in shown example).
- Improved cache hit behavior correlated with lower read latency and reduced memory bandwidth pressure.
- Disabling allocating inbound writes reduced performance (~16% degradation in shown example), increased memory pressure, and increased latency.

## 6 Tools

Tools discussed:
- Intel(R) VTune(TM) Profiler
- Linux perf (`perf stat -M ...`)
- Intel(R) PCM (PCM-PCIe / PCM-IIO)

## 7 Conclusion

DDIO can significantly improve I/O performance, but because it is transparent to software, PMU/PerfMon analysis is necessary to measure and optimize effectiveness.

## 8 Notices and Disclaimers

The article includes Intel legal/performance disclaimers and references.

## 9 References

Main references cited in article:
- Sapphire Rapids Uncore PMU Programming Guide
- Intel perfmon GitHub repository
- VTune cookbook article on effective DDIO utilization
- Intel PCM article

## Appendix

Includes example system configuration for the iperf DDIO study and additional product/performance information.

---

## Note

This Markdown file is a structured conversion/synthesis of the linked Intel article content for local use.
For the complete authoritative text, figures, and tables, refer to the source URL above.
