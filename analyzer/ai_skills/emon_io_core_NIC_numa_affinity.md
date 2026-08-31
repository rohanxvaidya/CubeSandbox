# EMON IO and Core numa affinity analysis Skill

This skill documents a repeatable workflow for processing one EMON dat file, filtering related metrics/events into a new workbook, preserving Excel formatting, and adding charts for `core view` and `cha uncore view`.


## Emon Events and Metrics

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
    UNC_CHA_TOR_INSERTS.IO_ITOM 
    UNC_CHA_TOR_INSERTS.IO_PCIRDCUR
    UNC_CHA_TOR_INSERTS.IO_PCIRDCUR_LOCAL


### In `core view` and `socket view` sheet

    L2_LINES_IN.ALL
    L2_LINES_OUT.USELESS_HWPF
    L2_RQSTS.ALL_CODE_RD
    L2_RQSTS.ALL_HWPF
    OCR.READS_TO_CORE.SNC_CACHE.HITM
    OCR.READS_TO_CORE.SNC_CACHE.HIT_WITH_FWD


### Cross numa access metrics: in the `core view` and `thread view` and `socket view` sheet
```    
    metric_NUMA % all reads to remote cluster memory
    metric_NUMA % all reads to local cluster memory
    metric_NUMA % all reads to remote cluster cache
    metric_NUMA % all reads to remote socket cache
    metric_NUMA % all reads to remote socket memory
    metric_NUMA % all reads to local cluster cache
```


## References

- IO analysis : [emon_io_inbound_read](./emon_io_inbound_read.md)
- Linked rule source: [emon_TMA](./emon_TMA.md), [emon_info](./emon_info.md) 
- Emon data format: [emon_format](./emon_format.md)
- Capature emon data and Processing tool: [emon_tool.sh](../emon_tool.sh)

## When To Use

- You have a source `*.dat` EMON file and want processed `*.csv` and `*.xlsx` output.
- You need to extract rows for listed metrics/events from specific sheets.
- You need a filtered workbook that:
  - keeps source number format and cell style,
  - keeps original row-1 header in each output sheet,
  - has no added metadata columns in data sheets,

## Inputs
 - TBD

## Output Location

- Create one run folder under source dat parent path:
  - `.../filter_run_<BASE>_<timestamp>/`
- Keep all generated files under:
  - `.../filter_run_<BASE>_<timestamp>/<BASE>/emon_<BASE>/`

## Procedure

1. Prepare run folder on remote.
2. Copy local `emon_tool.sh` to remote run folder and set executable permission.
3. Copy source dat into `run/<BASE>/emon_<BASE>/<BASE>.dat`.
4. Run processing:
   - `cd run/<BASE>`
   - `bash ../emon_tool.sh pro <BASE>`
5. Verify output `<BASE>.xlsx` exists.
6. Parse filter rules from markdowns:
7. Filter by corresponding sheets only:
   - `cha/system/socket` target group -> only from `cha uncore view`, `system view`, `socket view`.
   - `iio` target group -> only from `iio uncore view`.
   - CPU metric group -> only from `core view`, `thread view`, `system view`, `socket view`.
   - `metric_TMA*` -> only from `core view`, `thread view`, `system view`, `socket view`.
8. Build filtered workbook with these constraints:
   - Data sheets contain only copied source rows (no metadata columns).
   - Keep original row-1 header in each output data sheet.
   - Preserve cell style/number format, column widths, and row heights while copying.
9. Add `operation_info` sheet with run summary:
   - input/output paths
   - row counts per sheet
   - missing targets
   - notes on formatting behavior
10. Add charts for generate charts:

## Expected Outputs

- Processed source workbook:
  - `<BASE>.xlsx`
- Filtered workbook (format preserved, header preserved, no metadata columns):
  - `<BASE>_filtered_rows_keep_format_header_info_<ts>.xlsx`
- Chart-enhanced workbook:
  - `<BASE>_filtered_rows_keep_format_header_info_<ts>_with_cha_row_charts_<ts>.xlsx`
- Optional json summaries:
  - `..._summary.json` files for traceability

## Validation Checklist


