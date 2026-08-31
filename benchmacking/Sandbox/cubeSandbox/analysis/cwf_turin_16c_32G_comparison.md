### Comparison and Analysis of CWF and Turin (16 vCPU + 32G Memory)

Benchmark command:
`./bin/cube-bench -c 30 -n 30000 -w 3 -o /tmp/cube.json`

----------------------------------------------
#### CWF: 16 vCPU + 32G, cube-bench 30c

```
[root@cwf-bkc ~]# perf stat --timeout 60000

 Performance counter stats for 'system wide':

        961,017.27 msec cpu-clock                        #   15.999 CPUs utilized
        14,791,854      context-switches                 #   15.392 K/sec
         1,702,328      cpu-migrations                   #    1.771 K/sec
        12,133,837      page-faults                      #   12.626 K/sec
 1,815,905,052,961      cycles                           #    1.890 GHz
 2,040,181,910,422      instructions                     #    1.12  insn per cycle
   439,281,271,294      branches                         #  457.100 M/sec
     6,640,121,096      branch-misses                    #    1.51% of all branches

      60.067076387 seconds time elapsed

```
Second sample:
```
[root@cwf-bkc ~]# perf stat --timeout 60000

 Performance counter stats for 'system wide':

        960,986.24 msec cpu-clock                        #   16.000 CPUs utilized
        14,721,742      context-switches                 #   15.319 K/sec
         1,707,770      cpu-migrations                   #    1.777 K/sec
        12,169,159      page-faults                      #   12.663 K/sec
 1,818,375,896,213      cycles                           #    1.892 GHz
 2,048,089,945,149      instructions                     #    1.13  insn per cycle
   440,859,605,202      branches                         #  458.757 M/sec
     6,636,113,349      branch-misses                    #    1.51% of all branches

      60.063087800 seconds time elapsed

```
Third sample:
```
perf stat --timeout 60000

 Performance counter stats for 'system wide':

        960,971.90 msec cpu-clock                        #   16.000 CPUs utilized
        14,743,960      context-switches                 #   15.343 K/sec
         1,704,024      cpu-migrations                   #    1.773 K/sec
        12,209,597      page-faults                      #   12.705 K/sec
 1,819,803,663,158      cycles                           #    1.894 GHz
 2,046,392,312,768      instructions                     #    1.12  insn per cycle
   440,715,151,609      branches                         #  458.614 M/sec
     6,644,860,564      branch-misses                    #    1.51% of all branches

      60.061884505 seconds time elapsed

```

----------------------------------------------
----------------------------------------------
#### Turin-D: 16 vCPU + 32G, cube-bench 30c

`./bin/cube-bench -c 30 -n 30000 -w 3 -o /tmp/cube.json`

```
perf stat --timeout 60000

 Performance counter stats for 'system wide':

        960,959.02 msec cpu-clock                        #   16.000 CPUs utilized
        10,204,692      context-switches                 #   10.619 K/sec
         1,194,450      cpu-migrations                   #    1.243 K/sec
         7,811,295      page-faults                      #    8.129 K/sec
 1,401,003,974,286      cycles                           #    1.458 GHz
   566,137,470,742      stalled-cycles-frontend          #   40.41% frontend cycles idle
 1,275,709,816,616      instructions                     #    0.91  insn per cycle
                                                  #    0.44  stalled cycles per insn
   239,192,757,837      branches                         #  248.910 M/sec
     4,611,701,147      branch-misses                    #    1.93% of all branches

      60.058789906 seconds time elapsed

Note: This sample may be inaccurate.
```
Second sample:
```
perf stat --timeout 60000

 Performance counter stats for 'system wide':

        961,009.37 msec cpu-clock                        #   16.000 CPUs utilized
        16,556,147      context-switches                 #   17.228 K/sec
         1,963,156      cpu-migrations                   #    2.043 K/sec
        12,782,663      page-faults                      #   13.301 K/sec
 2,300,932,194,528      cycles                           #    2.394 GHz
   928,097,098,876      stalled-cycles-frontend          #   40.34% frontend cycles idle
 2,099,281,104,449      instructions                     #    0.91  insn per cycle
                                                  #    0.44  stalled cycles per insn
   393,382,851,083      branches                         #  409.343 M/sec
     7,577,112,292      branch-misses                    #    1.93% of all branches

      60.063011205 seconds time elapsed
```
Third sample:
```
perf stat --timeout 60000

 Performance counter stats for 'system wide':

        960,972.60 msec cpu-clock                        #   16.000 CPUs utilized
        16,546,351      context-switches                 #   17.218 K/sec
         1,983,573      cpu-migrations                   #    2.064 K/sec
        12,800,391      page-faults                      #   13.320 K/sec
 2,300,305,969,656      cycles                           #    2.394 GHz
   926,570,451,314      stalled-cycles-frontend          #   40.28% frontend cycles idle
 2,090,886,099,355      instructions                     #    0.91  insn per cycle
                                                  #    0.44  stalled cycles per insn
   391,747,299,619      branches                         #  407.657 M/sec
     7,578,927,097      branch-misses                    #    1.93% of all branches

      60.060292683 seconds time elapsed

```

----------------------------------------------
----------------------------------------------
#### SRF-AP: 16 vCPU + 32G, cube-bench 30c

`./bin/cube-bench -c 30 -n 30000 -w 3 -o /tmp/cube.json`
First sample:
```
 perf stat --timeout 60000

 Performance counter stats for 'system wide':

        960,978.65 msec cpu-clock                        #   16.000 CPUs utilized
        11,285,129      context-switches                 #   11.743 K/sec
         1,249,236      cpu-migrations                   #    1.300 K/sec
         8,973,438      page-faults                      #    9.338 K/sec
 1,732,599,147,880      cycles                           #    1.803 GHz
 1,597,520,557,613      instructions                     #    0.92  insn per cycle
   340,190,345,977      branches                         #  354.004 M/sec
     5,889,160,125      branch-misses                    #    1.73% of all branches

      60.062133034 seconds time elapsed

```
Second sample:
```
 perf stat --timeout 60000

 Performance counter stats for 'system wide':

        960,970.32 msec cpu-clock                        #   16.000 CPUs utilized
        11,316,506      context-switches                 #   11.776 K/sec
         1,256,004      cpu-migrations                   #    1.307 K/sec
         8,953,416      page-faults                      #    9.317 K/sec
 1,735,138,125,920      cycles                           #    1.806 GHz
 1,597,520,597,293      instructions                     #    0.92  insn per cycle
   340,086,583,283      branches                         #  353.899 M/sec
     5,879,519,517      branch-misses                    #    1.73% of all branches

      60.062479465 seconds time elapsed

```

Third sample:
```
perf stat --timeout 60000

 Performance counter stats for 'system wide':

        960,993.33 msec cpu-clock                        #   16.000 CPUs utilized
        11,288,164      context-switches                 #   11.746 K/sec
         1,251,197      cpu-migrations                   #    1.302 K/sec
         8,954,199      page-faults                      #    9.318 K/sec
 1,736,124,247,666      cycles                           #    1.807 GHz
 1,597,565,447,490      instructions                     #    0.92  insn per cycle
   340,082,431,661      branches                         #  353.886 M/sec
     5,878,133,143      branch-misses                    #    1.73% of all branches

      60.060734924 seconds time elapsed

```

### Comparison

#### Third-Sample Summary Table (CWF vs Turin)

| Metric | CWF (3rd) | Turin (3rd) | Delta (Turin - CWF) | Delta % vs CWF |
|---|---:|---:|---:|---:|
| cpu-clock (msec) | 960,971.90 | 960,972.60 | +0.70 | +0.00% |
| CPUs utilized | 16.000 | 16.000 | 0.000 | +0.00% |
| context-switches | 14,743,960 | 16,546,351 | +1,802,391 | +12.22% |
| context-switches rate (K/sec) | 15.343 | 17.218 | +1.875 | +12.22% |
| cpu-migrations | 1,704,024 | 1,983,573 | +279,549 | +16.41% |
| cpu-migrations rate (K/sec) | 1.773 | 2.064 | +0.291 | +16.41% |
| page-faults | 12,209,597 | 12,800,391 | +590,794 | +4.84% |
| page-faults rate (K/sec) | 12.705 | 13.320 | +0.615 | +4.84% |
| cycles | 1,819,803,663,158 | 2,300,305,969,656 | +480,502,306,498 | +26.40% |
| frequency (GHz) | 1.894 | 2.394 | +0.500 | +26.40% |
| stalled-cycles-frontend | N/A | 926,570,451,314 | N/A | N/A |
| frontend stalled ratio | N/A | 40.28% | N/A | N/A |
| instructions | 2,046,392,312,768 | 2,090,886,099,355 | +44,493,786,587 | +2.17% |
| IPC (insn per cycle) | 1.12 | 0.91 | -0.21 | -18.75% |
| stalled cycles per insn | N/A | 0.44 | N/A | N/A |
| branches | 440,715,151,609 | 391,747,299,619 | -48,967,851,990 | -11.11% |
| branches rate (M/sec) | 458.614 | 407.657 | -50.957 | -11.11% |
| branch-misses | 6,644,860,564 | 7,578,927,097 | +934,066,533 | +14.06% |
| branch-miss rate | 1.51% | 1.93% | +0.42 pct-pt | +27.81% |
| time elapsed (sec) | 60.061884505 | 60.060292683 | -0.001591822 | -0.00% |

#### Direction Table (High/Low Quick View)

| Category | Better Direction | CWF | Turin | Note |
|---|---|---:|---:|---|
| Throughput (total instructions) | Higher | 2.046e12 | 2.091e12 | Turin has slightly higher total instructions |
| Core efficiency (IPC) | Higher | 1.12 | 0.91 | CWF has clearly higher IPC |
| Scheduler stability (context switch, migration) | Lower | Lower | Higher | CWF has lower switching and migration pressure |
| Memory-fault pressure (page-faults) | Lower | Lower | Higher | CWF has lower page-fault activity |
| Branch quality (miss rate) | Lower | 1.51% | 1.93% | CWF has better branch behavior |
| Frequency/cycles | Depends on objective | Lower | Higher | Turin consumes more cycles at higher GHz |

#### Extended Comparison

Use the same table-header format to compare CWF vs Turin vs SRF-AP based on third-sample data.

| Metric | CWF (30c) | Turin (30c) | SRF-AP (30c) | Comparative Conclusion | Metric Significance |
|---|---:|---:|---:|---|---|
| cpu-clock (msec) | 960,971.90 | 960,972.60 | 960,993.33 | Nearly identical across all three | Total CPU time in the sampling window; used to confirm comparability |
| CPUs utilized | 16.000 | 16.000 | 16.000 | Identical across all three | Effective core usage under the same resource allocation |
| context-switches | 14,743,960 | 16,546,351 | 11,288,164 | Highest on Turin, lowest on SRF-AP | Task-switch frequency; higher values usually imply higher scheduling overhead |
| context-switches rate (K/sec) | 15.343 | 17.218 | 11.746 | Highest on Turin, lowest on SRF-AP | Per-time switching intensity; reflects scheduler activity |
| cpu-migrations | 1,704,024 | 1,983,573 | 1,251,197 | Highest on Turin, lowest on SRF-AP | Cross-core thread migrations; higher values may hurt cache locality |
| cpu-migrations rate (K/sec) | 1.773 | 2.064 | 1.302 | Highest on Turin, lowest on SRF-AP | Migration intensity; reflects scheduling stability |
| page-faults | 12,209,597 | 12,800,391 | 8,954,199 | Highest on Turin, lowest on SRF-AP | Page-fault activity; reflects memory access/mapping disturbance |
| page-faults rate (K/sec) | 12.705 | 13.320 | 9.318 | Highest on Turin, lowest on SRF-AP | Per-time page-fault pressure |
| cycles | 1,819,803,663,158 | 2,300,305,969,656 | 1,736,124,247,666 | Highest on Turin, lowest on SRF-AP | Total consumed cycles, jointly affected by frequency and efficiency |
| frequency (GHz) | 1.894 | 2.394 | 1.807 | Highest on Turin, lowest on SRF-AP | Average operating frequency; indicates clock-driving capability |
| instructions | 2,046,392,312,768 | 2,090,886,099,355 | 1,597,565,447,490 | Turin slightly exceeds CWF; SRF-AP is notably lower | Total retired instructions; approximates aggregate throughput |
| IPC (insn per cycle) | 1.12 | 0.91 | 0.92 | Highest on CWF, lowest on Turin | Effective instructions per cycle; measures core execution efficiency |
| branches | 440,715,151,609 | 391,747,299,619 | 340,082,431,661 | Highest on CWF, lowest on SRF-AP | Branch-instruction volume; reflects control-flow workload |
| branches rate (M/sec) | 458.614 | 407.657 | 353.886 | Highest on CWF, lowest on SRF-AP | Branch execution density per unit time |
| branch-misses | 6,644,860,564 | 7,578,927,097 | 5,878,133,143 | Highest on Turin, lowest on SRF-AP | Branch prediction failures; higher values imply more front-end waste |
| branch-miss rate | 1.51% | 1.93% | 1.73% | Best on CWF, worst on Turin, SRF-AP in between | Branch prediction quality; directly impacts pipeline efficiency |
| stalled-cycles-frontend | N/A | 926,570,451,314 | N/A | Available only on Turin | Front-end stall cycles; indicates fetch/decode bottlenecks |
| frontend stalled ratio | N/A | 40.28% | N/A | Available only on Turin | Front-end idle ratio; higher values suggest insufficient front-end supply |
| stalled cycles per insn | N/A | 0.44 | N/A | Available only on Turin | Stall cost per instruction; indicates execution blocking |
| time elapsed (sec) | 60.061884505 | 60.060292683 | 60.060734924 | Consistent across all three | Actual sample duration; ensures horizontal comparability |

One-line conclusion:
Under 16 vCPU + 32G with the same 30c workload, Turin shows the highest frequency and cycle consumption, CWF delivers the best IPC and branch-miss rate, and SRF-AP exhibits the lowest scheduling and memory-fault pressure but also the lowest instruction throughput.

---------------

### Result: CWF vs SRF-AP vs Turin

Understood. No source-file changes are made in that note. Below is the direct third-sample comparison across the three platforms, using the requested table format:

| Metric | CWF (30c) | Turin (30c) | SRF-AP (30c) | Comparative Conclusion | Metric Significance |
|---|---:|---:|---:|---|---|
| cpu-clock (msec) | 960,971.90 | 960,972.60 | 960,993.33 | Nearly identical across all three | Total CPU time in the sampling window; used to confirm comparability |
| CPUs utilized | 16.000 | 16.000 | 16.000 | Identical across all three | Effective core usage under the same resource allocation |
| context-switches | 14,743,960 | 16,546,351 | 11,288,164 | Highest on Turin, lowest on SRF-AP | Task-switch frequency; higher values usually imply higher scheduling overhead |
| context-switches rate (K/sec) | 15.343 | 17.218 | 11.746 | Highest on Turin, lowest on SRF-AP | Per-time switching intensity; reflects scheduler activity |
| cpu-migrations | 1,704,024 | 1,983,573 | 1,251,197 | Highest on Turin, lowest on SRF-AP | Cross-core thread migrations; higher values may affect cache locality |
| cpu-migrations rate (K/sec) | 1.773 | 2.064 | 1.302 | Highest on Turin, lowest on SRF-AP | Migration intensity; reflects scheduling stability |
| page-faults | 12,209,597 | 12,800,391 | 8,954,199 | Highest on Turin, lowest on SRF-AP | Page-fault activity; reflects memory access/mapping disturbance |
| page-faults rate (K/sec) | 12.705 | 13.320 | 9.318 | Highest on Turin, lowest on SRF-AP | Per-time page-fault pressure |
| cycles | 1,819,803,663,158 | 2,300,305,969,656 | 1,736,124,247,666 | Highest on Turin, lowest on SRF-AP | Total consumed cycles, jointly affected by frequency and efficiency |
| frequency (GHz) | 1.894 | 2.394 | 1.807 | Highest on Turin, lowest on SRF-AP | Average operating frequency; indicates clock-driving capability |
| instructions | 2,046,392,312,768 | 2,090,886,099,355 | 1,597,565,447,490 | Turin slightly exceeds CWF; SRF-AP is notably lower | Total retired instructions; approximates aggregate throughput |
| IPC (insn per cycle) | 1.12 | 0.91 | 0.92 | Highest on CWF, lowest on Turin; SRF-AP slightly above Turin | Effective instructions per cycle; measures core execution efficiency |
| branches | 440,715,151,609 | 391,747,299,619 | 340,082,431,661 | Highest on CWF, lowest on SRF-AP | Branch-instruction volume; reflects control-flow workload |
| branches rate (M/sec) | 458.614 | 407.657 | 353.886 | Highest on CWF, lowest on SRF-AP | Branch execution density per unit time |
| branch-misses | 6,644,860,564 | 7,578,927,097 | 5,878,133,143 | Highest on Turin, lowest on SRF-AP | Branch prediction failures; higher values imply more front-end waste |
| branch-miss rate | 1.51% | 1.93% | 1.73% | Best on CWF, worst on Turin, SRF-AP in between | Branch prediction quality; directly impacts pipeline efficiency |
| stalled-cycles-frontend | N/A | 926,570,451,314 | N/A | Available only on Turin | Front-end stall cycles; indicates fetch/decode bottlenecks |
| frontend stalled ratio | N/A | 40.28% | N/A | Available only on Turin | Front-end idle ratio; higher values suggest insufficient front-end supply |
| stalled cycles per insn | N/A | 0.44 | N/A | Available only on Turin | Stall cost per instruction; indicates execution blocking |
| time elapsed (sec) | 60.061884505 | 60.060292683 | 60.060734924 | Consistent across all three | Actual sample duration; ensures horizontal comparability |

One-line summary: Turin has the highest frequency and cycle count, as well as the highest scheduling/migration/page-fault activity; CWF has the best IPC and branch quality; SRF-AP has the lowest overall activity intensity but also the lowest total instruction throughput.