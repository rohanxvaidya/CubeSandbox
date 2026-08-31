# EMON Current Redis Benchmark Analysis

- current capture: emon_hitm_current_redis_bench_20260515_005615.txt (rows=20, cores=238)
- references: loaded2 / force1 / manual sw_numa=1

## Effective interval total (40-79)
- loaded2: 16,785,236.25
- force1: 22,793,006.15
- manual sw_numa=1: 19,121,245.75
- current: 26,564,774.30
- current vs loaded2: 58.26%
- current vs force1: 16.55%
- current vs manual sw_numa=1: 38.93%

## Global total (all cores)
- loaded2: 22,408,148.35
- force1: 34,161,821.70
- manual sw_numa=1: 25,775,818.95
- current: 50,547,086.15
- current vs loaded2: 125.57%
- current vs force1: 47.96%
- current vs manual sw_numa=1: 96.10%

## Split metrics in 40-79
- current split: 40-57 | 58-79
- current front/back mean: 1,123,208.46 / 288,501.00
- current front/back ratio: 3.89x
- current front/back shares: 76.11% / 23.89%

## p95 hotspots
- current threshold: 1,286,685.86, cores: [0, 3, 6, 8, 10, 12, 26, 27, 46, 48, 51, 80]
- overlap with loaded2: 2 / 12
- overlap with force1: 3 / 12
- overlap with manual sw_numa=1: 2 / 12
