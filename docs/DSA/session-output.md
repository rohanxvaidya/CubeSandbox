# Session Output Report

Date: 2026-04-02
Project: dsa-perf-micros

## 1) User requests handled in this session

1. Read src code and explain full code flow for:
   ./src/dsa_perf_micros -k 6 -u -i 1000 -n 128 -s 1024k -o3 -w 0
2. Re-check with DSA background and provide detailed function-call flow.
3. Run test directly on current system (vfio-pci already bound).
4. Add logging and verify runtime code flow.
5. Compare uio vs vfio-pci differences and code-level config differences.
6. Put comparison into Markdown.
7. Explain how to view flowchart TD diagrams.
8. Put all output in this session into a Markdown file.

## 2) Source discovery output

Source folder files discovered:
- common.h
- cpu.c
- device.c
- dsa.h
- idxd.h
- idxd_device.c
- init.c
- log.c
- main.c
- options.c
- prep.c
- user_device.c
- util.c
- headers and build artifacts in src

## 3) Key static-analysis conclusions

1. Entry point is main in src/main.c.
2. CLI parsing path:
   main -> do_options -> parse_options -> do_getopt -> validate_options.
3. For this command:
   -k 6 => one worker pinned to CPU 6.
   -u => USER driver path selected.
   -i 1000 => 1000 iterations.
   -n 128 => 128 buffers.
   -s 1024k => transfer size 1048576 bytes.
   -o3 => opcode value 3.
   -w 0 => dedicated work queue mode.
4. Opcode mapping was verified from linux idxd uapi header:
   DSA_OPCODE_MEMMOVE is value 3.
5. USER driver dispatch path:
   driver_init -> user_driver_init.
6. VFIO initialization path used in this run:
   ud_wq_find -> common_init -> vfio_init -> vfio_setup_device -> init_pci_device.
7. Descriptor prep path for op 3:
   do_desc_work -> test_prep_desc -> prep_dsa_memmove -> init_buffers -> init_memmove_desc_addr.
8. Submission/loop path:
   submit_test_desc -> do_single_iter -> submit_b2e repeated.
9. Result path:
   do_results -> print_results.

## 4) Non-trace runtime command executed

Command run:
DSA_PERF_MICROS_LOG_LEVEL=debug ./src/dsa_perf_micros -k 6 -u -i 1000 -n 128 -s 1024k -o3 -w 0

Observed important output:
- Device path showed vfio init messages.
- CPU 6 WQ configured with size 256, qd 128.
- Preparation/submission/verify phases completed.
- Final metrics:
  GB per sec = 53.647789
  cpu = 25.993704
  kopsrate = 51

## 5) Flow-trace run and outputs

Flow trace env used:
- DSA_PERF_MICROS_FLOW_TRACE=1
- DSA_PERF_MICROS_LOG_LEVEL=debug

Trace run output file:
- /tmp/dsa_flow_trace.log

Trace file size:
- 43283 lines

Startup trace excerpt:
- FLOW main argc=13
- FLOW do_options argc=13
- FLOW parse_options argc=13
- FLOW do_getopt argc=13
- FLOW fixup_options op=3
- FLOW validate_options op=3 nb_bufs=128 blen=1048576
- FLOW test_init_global nb_cpus=1 driver=1
- FLOW driver_init driver=1
- FLOW user_driver_init nb_user_eng=-1
- FLOW vfio_dev_count
- FLOW test_init_mem nb_cpus=1 nb_numa_node=2
- FLOW test_run nb_cpus=1
- FLOW test_fn
- FLOW test_init_fn
- FLOW test_init_percpu cpu=6
- FLOW test_init_wq cpu=6 requested_wq=-1
- FLOW wq_map dname=(auto) wq_id=-1 shared=0 numa=0
- FLOW ud_wq_get
- FLOW ud_wq_find dname=(auto) wq_id=-1 shared=0 numa=0
- FLOW common_init uio_cnt=0 bdf=0000:00:01.0
- FLOW vfio_init bdf=0000:00:01.0

Trace-derived call counts:
- submit_b2e: 41268
- do_single_iter: 1001
- user_virt2iova: 384
- rte_mem_virt2iova: 384
- init_memmove_desc_addr: 128
- ud_dmap: 4
- dmap: 4
- cpu_pin: 3
- run_check: 2
- all other control-path functions: 1 each

Trace-run final metrics:
- GB per sec = 2.696936
- cpu = 98.015968
- kopsrate = 2

Note: this lower performance is expected due to heavy flow logging overhead.

## 6) UIO vs VFIO code-level differences delivered

Major differences documented:
1. Driver counting and mixed-mode rejection in user_driver_init.
2. UIO path uses uio_init, sysfs resource mapping, and dpdk_init.
3. VFIO path uses vfio_init, VFIO group/container setup, VFIO IOMMU type1.
4. UIO sets dmap_fd = -1 and skips VFIO DMA map operations.
5. VFIO stores container fd and uses ud_dmap and ud_dunmap ioctls.
6. Address translation differs:
   vfio returns VA as IOVA in user_virt2iova;
   uio uses pagemap-based physical translation.
7. App iommu behavior differs through ud_iommu_disabled and iommu_disabled.

Detailed comparison file created:
- uio-vfio-driver-differences.md

## 7) Flowchart display guidance delivered

Ways provided:
1. VS Code Markdown preview.
2. Mermaid Live Editor.
3. Git hosting markdown rendering support.

## 8) Files created in this session

1. uio-vfio-driver-differences.md
2. session-output.md

## 9) Final status

All requested analyses and documentation tasks in this session were completed, including code flow tracing, live execution validation, uio-vfio comparison, and markdown artifacts.
