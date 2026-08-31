# EMON Compare: open_channel force node1 experiment

- before capture: emon_hitm_current_redis_bench_20260515_005615.txt (rows=20, cores=238)
- after capture: emon_hitm_openchannel_force_node1_20260515_010503.txt (rows=20, cores=238)

## Effective interval total (40-79)
- before: 26,564,774.30
- after: 27,390,948.55
- delta: 826,174.25 (3.11%)

## Global total (all cores)
- before: 50,547,086.15
- after: 36,351,007.30
- delta: -14,196,078.85 (-28.08%)

## Split metrics in 40-79
- before split: 40-57 | 58-79
- after split: 40-57 | 58-79
- before front/back mean: 1,123,208.46 / 288,501.00 (ratio 3.89x)
- after front/back mean: 1,131,236.14 / 319,486.27 (ratio 3.54x)
- before shares: 76.11% / 23.89%
- after shares: 74.34% / 25.66%

## p95 hotspots
- before threshold: 1,286,685.86, cores: [0, 3, 6, 8, 10, 12, 26, 27, 46, 48, 51, 80]
- after threshold: 1,102,703.60, cores: [38, 45, 46, 49, 50, 51, 52, 53, 54, 57, 163, 227]
- overlap: 2 / before 12 / after 12
