# HITM After-Patch Comparison

- new capture: emon_hitm_capture_after_patch_20260514_224849.txt
- new samples: 20
- parsed cores/sample: 238
- baseline stats source: emon_hitm_per_core_stats_rerun.csv

## Effective range split (40-79)
- baseline split: 40-57 | 58-79
- after-patch split: 40-57 | 58-79

### Segment means and shares
- baseline front mean: 1,182,029.17
- after-patch front mean: 428,993.76
- delta front mean: -753,035.40 (-63.71%)

- baseline back mean: 213,298.62
- after-patch back mean: 139,209.26
- delta back mean: -74,089.36 (-34.74%)

- baseline ratio front/back: 5.54x
- after-patch ratio front/back: 3.08x
- baseline share front/back: 81.93% / 18.07%
- after-patch share front/back: 71.60% / 28.40%

## Hotspot comparison
- baseline p95 threshold: 1,171,123.00, cores: [38, 40, 42, 45, 46, 49, 50, 51, 52, 55, 57, 178]
- after-patch p95 threshold: 455,008.95, cores: [3, 38, 39, 42, 46, 51, 53, 54, 56, 83, 84, 120]
- p95 overlap count: 4 / baseline 12 / after 12
- after-patch p95 in 40-79: [42, 46, 51, 53, 54, 56]

- baseline p99 threshold: 1,346,724.30, cores: [40, 42, 178]
- after-patch p99 threshold: 749,942.34, cores: [3, 46, 51]
- p99 overlap count: 0 / baseline 3 / after 3
