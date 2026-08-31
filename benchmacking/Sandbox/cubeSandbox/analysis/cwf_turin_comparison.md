### CWF-AP: run case 250 concurrency

---------------------------------------------
CWF  250 == 200ms. 
```
perf stat --timeout 60000

 Performance counter stats for 'system wide':

     17,312,829.01 msec cpu-clock                        #  287.977 CPUs utilized
       123,950,460      context-switches                 #    7.159 K/sec
        14,356,747      cpu-migrations                   #  829.255 /sec
        92,488,383      page-faults                      #    5.342 K/sec
23,015,141,200,439      instructions                     #    0.89  insn per cycle
26,004,463,498,949      cycles                           #    1.502 GHz
 4,782,053,351,258      branches                         #  276.214 M/sec
    64,397,554,701      branch-misses                    #    1.35% of all branches

      60.118756740 seconds time elapsed

```
---------------------------------------------
### Turin-384c : cube-bench 250 concurrency

```
 perf stat --timeout 60000

 Performance counter stats for 'system wide':

     23,086,406.98 msec cpu-clock                        #  384.284 CPUs utilized
        26,735,086      context-switches                 #    1.158 K/sec
         2,171,314      cpu-migrations                   #   94.052 /sec
        18,743,639      page-faults                      #  811.891 /sec
 8,329,234,445,037      cycles                           #    0.361 GHz
 1,201,098,502,768      stalled-cycles-frontend          #   14.42% frontend cycles idle
 3,457,451,663,153      instructions                     #    0.42  insn per cycle
                                                  #    0.35  stalled cycles per insn
   671,089,417,601      branches                         #   29.069 M/sec
    10,295,464,516      branch-misses                    #    1.53% of all branches

      60.076394752 seconds time elapsed

```



---------------------------------------------
----------------------------------------------
#### SRF-AP,  full cores , cube-bench 250c   

`./bin/cube-bench -c 250 -n 300000 -w 3 -o /tmp/cube.json `
--- 1st sampling

```
 perf stat --timeout 60000
 Performance counter stats for 'system wide':

     17,314,932.20 msec cpu-clock                        #  287.992 CPUs utilized
       106,565,248      context-switches                 #    6.155 K/sec
        12,245,575      cpu-migrations                   #  707.226 /sec
        77,667,102      page-faults                      #    4.486 K/sec
20,049,369,711,566      cycles                           #    1.158 GHz
14,769,148,420,126      instructions                     #    0.74  insn per cycle
 3,162,207,705,952      branches                         #  182.629 M/sec
    50,813,403,521      branch-misses                    #    1.61% of all branches

      60.122955271 seconds time elapsed

```

--- 2nd samplling.
```
 perf stat --timeout 60000

  Performance counter stats for 'system wide':

     17,309,441.21 msec cpu-clock                        #  287.989 CPUs utilized
       105,985,784      context-switches                 #    6.123 K/sec
        12,143,937      cpu-migrations                   #  701.579 /sec
        77,559,531      page-faults                      #    4.481 K/sec
20,047,261,027,872      cycles                           #    1.158 GHz
14,791,542,569,464      instructions                     #    0.74  insn per cycle
 3,162,066,198,513      branches                         #  182.679 M/sec
    51,190,050,860      branch-misses                    #    1.62% of all branches

      60.104464616 seconds time elapsed


```

3rd sampling
```
perf stat --timeout 60000

 Performance counter stats for 'system wide':

     17,309,785.25 msec cpu-clock                        #  287.960 CPUs utilized
       107,241,000      context-switches                 #    6.195 K/sec
        12,307,816      cpu-migrations                   #  711.032 /sec
        78,577,061      page-faults                      #    4.539 K/sec
20,273,386,764,489      cycles                           #    1.171 GHz
14,964,138,452,827      instructions                     #    0.74  insn per cycle
 3,198,458,940,545      branches                         #  184.778 M/sec
    51,929,600,972      branch-misses                    #    1.62% of all branches

      60.111722863 seconds time elapsed

```

----------------------------------------------
#### SRF-AP,  full cores , cube-bench 300c   

`./bin/cube-bench -c 250 -n 300000 -w 3 -o /tmp/cube.json `
```
perf stat --timeout 60000

 Performance counter stats for 'system wide':

     17,291,512.17 msec cpu-clock                        #  288.046 CPUs utilized
       106,013,981      context-switches                 #    6.131 K/sec
        12,341,141      cpu-migrations                   #  713.711 /sec
        77,519,902      page-faults                      #    4.483 K/sec
20,077,516,096,357      cycles                           #    1.161 GHz
14,771,339,529,254      instructions                     #    0.74  insn per cycle
 3,164,450,863,205      branches                         #  183.006 M/sec
    50,387,284,991      branch-misses                    #    1.59% of all branches

      60.030397292 seconds time elapsed

[root@srf-bkc ~]# perf stat --timeout 60000

 Performance counter stats for 'system wide':

     17,314,729.36 msec cpu-clock                        #  287.991 CPUs utilized
       108,136,723      context-switches                 #    6.245 K/sec
        12,504,284      cpu-migrations                   #  722.176 /sec
        79,480,261      page-faults                      #    4.590 K/sec
20,547,841,317,923      cycles                           #    1.187 GHz
15,083,467,214,928      instructions                     #    0.73  insn per cycle
 3,225,299,144,650      branches                         #  186.275 M/sec
    52,132,629,521      branch-misses                    #    1.62% of all branches

      60.122491571 seconds time elapsed

[root@srf-bkc ~]# perf stat --timeout 60000

 Performance counter stats for 'system wide':

     17,306,927.46 msec cpu-clock                        #  287.916 CPUs utilized
        44,494,459      context-switches                 #    2.571 K/sec
         6,144,921      cpu-migrations                   #  355.056 /sec
        16,583,557      page-faults                      #  958.203 /sec
 8,392,529,097,475      cycles                           #    0.485 GHz
 5,772,872,961,126      instructions                     #    0.69  insn per cycle
 1,215,173,633,685      branches                         #   70.213 M/sec
    33,116,764,130      branch-misses                    #    2.73% of all branches

      60.111122393 seconds time elapsed

```

### Comparison

#### CWF vs Turin Analysis (250 Concurrency)

This comparison uses the metrics shown above in this file.

Important note: `time elapsed` is nearly equal (`60.1188s` on CWF vs `60.0764s` on Turin), but CPU utilization is significantly different (`287.977` vs `384.284`). For this reason, normalized metrics (`K/sec`, `/sec`, `IPC`, `GHz`, and `%`) are more reliable than raw totals.

| Metric | CWF (250c) | Turin (250c) | Comparison Conclusion | Metric Significance |
|---|---:|---:|---|---|
| cpu-clock (msec) | 17,312,829.01 | 23,086,406.98 | Turin is higher due to higher CPU parallelism | Cumulative CPU runtime across all cores |
| CPUs utilized | 287.977 | 384.284 | Turin uses substantially more parallel CPU resources | Effective average parallel CPU usage |
| context-switches | 123,950,460 | 26,735,086 | CWF is higher in total | Total scheduler context-switch count |
| context-switches rate (K/sec) | 7.159 | 1.158 | Turin is much lower per second | Scheduler activity intensity |
| cpu-migrations | 14,356,747 | 2,171,314 | Turin is much lower | Thread movement across cores |
| cpu-migrations rate (/sec) | 829.255 | 94.052 | Turin is much lower per second | Migration pressure and cache-locality disturbance |
| page-faults | 92,488,383 | 18,743,639 | Turin is much lower in total | Total page-fault activity |
| page-faults rate (K/sec) | 5.342 | 0.812 | Turin is much lower per second | Memory fault pressure |
| cycles | 26,004,463,498,949 | 8,329,234,445,037 | CWF is much higher | Total consumed cycles |
| frequency (GHz) | 1.502 | 0.361 | CWF is significantly higher | Average effective operating frequency |
| instructions | 23,015,141,200,439 | 3,457,451,663,153 | CWF is much higher | Total retired instructions |
| IPC (insn per cycle) | 0.89 | 0.42 | CWF is clearly higher | Core execution efficiency |
| branches | 4,782,053,351,258 | 671,089,417,601 | CWF is much higher | Branch instruction workload |
| branches rate (M/sec) | 276.214 | 29.069 | CWF is much higher per second | Branch processing throughput |
| branch-misses | 64,397,554,701 | 10,295,464,516 | CWF is higher in total misses due to much higher branch volume | Total branch mispredictions |
| branch-miss rate | 1.35% | 1.53% | CWF is better | Branch prediction quality |
| stalled-cycles-frontend | N/A | 1,201,098,502,768 | Available only on Turin | Front-end stall cycles |
| frontend stalled ratio | N/A | 14.42% | Available only on Turin | Front-end idle/stall share |
| stalled cycles per insn | N/A | 0.35 | Available only on Turin | Stall cost per instruction |
| time elapsed (sec) | 60.118756740 | 60.076394752 | Nearly equal elapsed time | Wall-clock runtime |

**CWF vs Turin Summary**
1. CWF shows much higher execution efficiency (`IPC 0.89 vs 0.42`) and much higher effective frequency (`1.502 GHz vs 0.361 GHz`).
2. CWF also delivers much higher branch throughput (`276.214 M/sec vs 29.069 M/sec`) and a better branch-miss rate (`1.35% vs 1.53%`).
3. Turin shows much lower scheduler and memory-fault rates, but this is accompanied by substantially lower throughput and efficiency in this capture.




### Result, CWF vs SRF vs Turin

#### CWF vs SRF-AP vs Turin Analysis

This three-platform comparison uses:
- CWF: the `CWF 250 == 200ms` sample above
- Turin: the `Turin-384c : cube-bench 250 concurrency` sample above
- SRF-AP: the `3rd sampling` under `cube-bench 250c`

Note: elapsed time is nearly identical across the selected samples, but Turin uses significantly more CPUs (`384.284` vs `287.977/287.960`). Normalized rates and efficiency metrics should therefore be prioritized over raw totals.

| Metric | CWF (250c) | Turin (250c) | SRF-AP (250c, 3rd) | Comparison Conclusion | Metric Significance |
|---|---:|---:|---:|---|---|
| cpu-clock (msec) | 17,312,829.01 | 23,086,406.98 | 17,309,785.25 | Turin is highest | Total CPU runtime in the measurement window |
| CPUs utilized | 287.977 | 384.284 | 287.960 | Turin is highest; CWF and SRF are similar | Effective average parallel CPU usage |
| context-switches | 123,950,460 | 26,735,086 | 107,241,000 | CWF is highest; Turin is lowest | Total scheduler switching volume |
| context-switches rate (K/sec) | 7.159 | 1.158 | 6.195 | CWF is highest; Turin is lowest | Scheduler activity per second |
| cpu-migrations | 14,356,747 | 2,171,314 | 12,307,816 | CWF is highest; Turin is lowest | Thread migration count |
| cpu-migrations rate (/sec) | 829.255 | 94.052 | 711.032 | CWF is highest; Turin is lowest | Migration pressure |
| page-faults | 92,488,383 | 18,743,639 | 78,577,061 | CWF is highest; Turin is lowest | Total page-fault activity |
| page-faults rate (K/sec) | 5.342 | 0.812 | 4.539 | CWF is highest; Turin is lowest | Memory fault pressure per second |
| cycles | 26,004,463,498,949 | 8,329,234,445,037 | 20,273,386,764,489 | CWF is highest; Turin is lowest | Total consumed cycles |
| frequency (GHz) | 1.502 | 0.361 | 1.171 | CWF is highest; Turin is lowest | Average effective frequency |
| instructions | 23,015,141,200,439 | 3,457,451,663,153 | 14,964,138,452,827 | CWF is highest; Turin is lowest | Total retired instructions |
| IPC (insn per cycle) | 0.89 | 0.42 | 0.74 | CWF is highest; Turin is lowest; SRF is in between | Core execution efficiency |
| branches | 4,782,053,351,258 | 671,089,417,601 | 3,198,458,940,545 | CWF is highest; Turin is lowest | Branch workload volume |
| branches rate (M/sec) | 276.214 | 29.069 | 184.778 | CWF is highest; Turin is lowest | Branch throughput per second |
| branch-misses | 64,397,554,701 | 10,295,464,516 | 51,929,600,972 | CWF is highest in total misses due to highest branch volume | Total branch mispredictions |
| branch-miss rate | 1.35% | 1.53% | 1.62% | CWF is best; SRF is worst | Branch prediction quality |
| stalled-cycles-frontend | N/A | 1,201,098,502,768 | N/A | Available only on Turin | Front-end stall cycles |
| frontend stalled ratio | N/A | 14.42% | N/A | Available only on Turin | Front-end idle/stall share |
| time elapsed (sec) | 60.118756740 | 60.076394752 | 60.111722863 | Nearly identical across all three | Wall-clock runtime |

**CWF vs SRF vs Turin Summary**
1. CWF has the strongest execution efficiency and throughput in this dataset: highest `IPC` (`0.89`), highest `GHz` (`1.502`), highest branch throughput, and best branch-miss rate (`1.35%`).
2. SRF-AP is consistently between CWF and Turin on efficiency/throughput (`IPC 0.74`, `1.171 GHz`), while showing lower scheduler and memory-fault pressure than CWF.
3. Turin shows the lowest scheduler and memory-fault activity, but also the lowest efficiency/throughput indicators (`IPC 0.42`, `0.361 GHz`, `29.069 M/sec branches`) in this capture.