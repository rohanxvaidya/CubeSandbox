# EMON Compare: Manual reload + sw_numa_node=1

- new capture: emon_hitm_after_manual_reload_swnuma1_20260514_231443.txt (rows=20, cores=238)
- compare refs: emon_hitm_capture_after_patch_loaded2_20260514_225052.txt, emon_hitm_compvec_force1_20260514_230522.txt

## Effective interval totals (40-79)
- loaded2: 16,785,236.25
- force1: 22,793,006.15
- manual sw_numa=1: 19,121,245.75
- new vs loaded2: 13.92%
- new vs force1: -16.11%

## Global totals (all cores)
- loaded2: 22,408,148.35
- force1: 34,161,821.70
- manual sw_numa=1: 25,775,818.95
- new vs loaded2: 15.03%
- new vs force1: -24.55%

## Split metrics (40-79 best split)
- loaded2: split 40-57 | 58-79, front/back mean 732,762.97/163,431.95, ratio 4.48x, shares 78.58%/21.42%
- force1: split 40-57 | 58-79, front/back mean 913,716.33/288,459.64, ratio 3.17x, shares 72.16%/27.84%
- manual sw_numa=1: split 40-57 | 58-79, front/back mean 799,544.50/214,974.76, ratio 3.72x, shares 75.27%/24.73%

## p95 hotspots
- loaded2 threshold: 780,383.37, cores: [3, 38, 39, 40, 42, 45, 46, 49, 50, 52, 54, 91]
- force1 threshold: 929,991.35, cores: [0, 12, 38, 39, 40, 41, 43, 50, 51, 56, 57, 121]
- manual sw_numa=1 threshold: 810,257.47, cores: [1, 38, 41, 46, 50, 51, 52, 53, 54, 55, 56, 124]
- overlap(new, loaded2): 5 / 12
- overlap(new, force1): 5 / 12
