# EMON Header Parse Prompt (Based on emon_info.md)

You are asked to parse system information from an EMON data file (`*.dat`).

## Task Goal

- Read and parse only the EMON header section.
- The header ends at the line containing `Version Info` (this is the last header line).
- Ignore event sample/body data after `Version Info`.
- Extract and summarize all available system HW/SW information.

## Input Pattern

- User typically provides:
  - A server node (for example `root@<ip>`), If data located on remote server.
  - A remote EMON file path, such as:
    - `/home/.../emon_xxx/<name>.dat`
- Dat file names can vary.

## Required Output Artifacts

Create a folder under local analyzer `emon_data` using the dat basename:

- Target folder:
  - `analyzer/emon_data/<dat_basename>/`

Put these files in that same folder:

- `<dat_basename>.dat` (local copy pulled from server)
- `<dat_basename>_header.txt` (header from first line through `Version Info`)
- `<dat_basename>_emon_info.md` (final parsed markdown report)

## Required Report Content

The markdown report should include all system information available in the header, including at least:

- Software/toolchain:
  - EMON version
  - Build date
  - SEP/PAX driver versions
  - Kernel version
  - Collection mode
- CPU/platform:
  - Family/model/stepping
  - Packages/cores/threads
  - online/total processors
  - architecture fields
- Cache topology
- PMU info:
  - Core counters/features
  - Uncore PMU units
  - RDT support
- Memory and DIMM layout
- NUMA topology and CPU mapping
- Interconnect and IO topology:
  - QPI/UPI links
  - IIO details
  - PCIe details
- Frequency information (TSC/base/max/turbo table)
- Final `Version Info` line

To avoid missing details, append the full raw header in the report as an appendix.

## Behavioral Requirements

- Do not ask for permission to install parsing tools if needed.
- Do not ask for permission to modify files inside created folders under `analyzer/emon_data/`.
- Keep output complete and traceable to source node/path.

## Acceptance Criteria

- Header is correctly cut at `Version Info`.
- HW/SW details are fully summarized in markdown.
- Dat copy, header extract, and markdown report are colocated in matching folder.
- Report is readable, structured, and complete.