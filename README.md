# Storage-performance-analysis

## Cluster Telemetry
Capature all of the node system monitor statistics in the cluster, and collect all of them in logs directory. For performance benchmark and analysis, people usually want to monitor the system with CPU/memory/IO/Networking runtime statistics. 
Run the command to start the telmetry function to collect system perf statistics.
```
run.sh --telem
```
Other parameters:
`delay_run`: will delay some seconds before collection, default is `0`.
```
run.sh --telem --delay_run=10s
```
`duration`: Time duration for logs collection, default is `100s`
```
run.sh --telem --delay_run=10s --duration=200s
```
`logpath`: where to put the logs which collected from cluster, default is local directory.
```
run.sh --telem --logpath=/opt/logs/
```

## Variable: 
NODE_AFFINITY: 0/1, disable/enable the pod deployment node affnity,  if it's enabeld, the node should add the label: `TELEMETRY_NODE=yes`
CASENAME:  used for sufix for the log path name. e.g. CASENAME="4k", then the log folder will be ${time}-log-4k