# EMON IO Inbound Read Skill

This skill documents a repeatable workflow for processing one EMON dat file, filtering related metrics/events into a new workbook, preserving Excel formatting, and adding charts for `cha uncore view`.

## References

- Rule source: [emon_io_inbound_read](./emon_io_inbound_read.md)
- Linked rule source: [emon_TMA](./emon_TMA.md)
- Format expectations: [emon_format](./emon_format.md)
- Capature emon data and Processing tool: [emon_tool.sh](../emon_tool.sh)

## When To Use

- You have a source `*.dat` EMON file and want processed `*.csv` and `*.xlsx` output.
- You need to extract rows for listed metrics/events from specific sheets.
- You need a filtered workbook that:
  - keeps source number format and cell style,
  - keeps original row-1 header in each output sheet,
  - has no added metadata columns in data sheets,
  - includes one line chart per data row in `cha uncore view`.

## Inputs

- `REMOTE_HOST`: e.g. `root@10.239.12.240`
- `DAT_PATH`: source dat path, e.g. `/home/mz/bytedance_rdma/emon_data/bytedance_0316/emon-bytenic-4k-195.dat`
- `BASE`: dat basename without `.dat`
- Local tool path: `analyzer/emon_tool.sh`

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
   - Explicit targets from `emon_io_inbound_read.md`.
   - Linked rule from `emon_TMA.md`: include all rows whose metric name starts with `metric_TMA`.
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
10. Add charts:
    - Create sheet `cha uncore view charts`.
    - For each non-header row in `cha uncore view`, insert one Excel line chart.
    - X-axis uses row-1 sample headers (columns 2..N).
    - Y-axis uses data from current row (columns 2..N).
    - Exclude row 1 (header) from chart generation.
    - Append chart summary into `operation_info`.

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

- `cha uncore view charts` exists.
- Chart count equals number of numeric data rows in `cha uncore view` excluding row 1.
- Data sheets do not include columns like `target`, `target_type`, `rule`, `source_row`, `source_col`.
- Row 1 header is present in every output data sheet.
- `operation_info` exists and includes missing targets and chart count.

## Known Missing Targets (May Be Absent In Source Workbook)

- `metric_IO bandwidth read local (MB/sec)`
- `UNC_CHA_TOR_INSERTS.IO_PCIRDCUR_LOCAL`

These should be reported in `operation_info` rather than silently ignored.