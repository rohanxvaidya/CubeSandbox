# HITM After-Patch (Loaded Module) Comparison

- new capture: emon_hitm_capture_after_patch_loaded2_20260514_225052.txt
- new samples: 20
- parsed cores/sample: 238
- baseline stats source: emon_hitm_per_core_stats_rerun.csv

## Effective interval (40-79) total
- baseline total(mean-sum over 40-79): 25,969,094.70
- after-patch total(mean-sum over 40-79): 16,785,236.25
- delta: -9,183,858.45 (-35.36%)

## Effective range split
- baseline split: 40-57 | 58-79
- after-patch split: 40-57 | 58-79
- baseline front/back mean: 1,182,029.17 / 213,298.62
- after-patch front/back mean: 732,762.97 / 163,431.95
- baseline ratio: 5.54x, shares: 81.93% / 18.07%
- after-patch ratio: 4.48x, shares: 78.58% / 21.42%

## Global total
- baseline total(mean-sum all cores): 32,083,284.10
- after-patch total(mean-sum all cores): 22,408,148.35
- delta: -9,675,135.75 (-30.16%)
