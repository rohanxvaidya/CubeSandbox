# EMON Compare: Previous Loaded vs comp_vector force node1

- previous capture: emon_hitm_capture_after_patch_loaded2_20260514_225052.txt (rows=20, cores=238)
- new capture: emon_hitm_compvec_force1_20260514_230522.txt (rows=20, cores=238)

## Effective interval total (40-79)
- previous: 16,785,236.25
- force1: 22,793,006.15
- delta: 6,007,769.90 (35.79%)

## Split metrics
- previous split: 40-57 | 58-79
- force1 split: 40-57 | 58-79
- previous front/back mean: 732,762.97 / 163,431.95
- force1 front/back mean: 913,716.33 / 288,459.64
- previous ratio: 4.48x, shares: 78.58% / 21.42%
- force1 ratio: 3.17x, shares: 72.16% / 27.84%

## p95 hotspot compare
- previous p95 threshold: 780,383.37, cores: [3, 38, 39, 40, 42, 45, 46, 49, 50, 52, 54, 91]
- force1 p95 threshold: 929,991.35, cores: [0, 12, 38, 39, 40, 41, 43, 50, 51, 56, 57, 121]
- overlap: 4 / prev 12 / force1 12
