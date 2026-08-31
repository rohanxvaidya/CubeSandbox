# EMON Compare: online sw_numa vs fixed spread(1)

- online capture: emon_hitm_online_compare_fresh_20260515_021827.txt (rows=20, cores=238)
- fixed1 capture: emon_hitm_fixed1_compare_fresh_retry_20260515_022030.txt (rows=20, cores=238)

## Effective interval total (40-79)
- online sw_numa: 19,455,671.80
- fixed spread(1): 18,423,249.50
- fixed1 vs online: -5.31%

## Global total (all cores)
- online sw_numa: 25,395,404.50
- fixed spread(1): 23,084,639.95
- fixed1 vs online: -9.10%

## Split metrics (40-79)
- online sw_numa: split 40-57 | 58-79, front/back mean 809,802.94/221,782.68, ratio 3.65x, shares 74.92%/25.08%
- fixed spread(1): split 40-57 | 58-79, front/back mean 760,657.59/215,064.22, ratio 3.54x, shares 74.32%/25.68%

## p95 hotspots
- online threshold: 812,250.48, cores: [5, 38, 39, 40, 42, 45, 49, 50, 52, 53, 55, 94]
- fixed threshold: 731,294.33, cores: [2, 38, 41, 42, 44, 47, 51, 53, 54, 56, 57, 224]
