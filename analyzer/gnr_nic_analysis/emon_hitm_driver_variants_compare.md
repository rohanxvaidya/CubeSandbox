# EMON Driver Variants Comparison

- hybrid capture: emon_hitm_openchannel_hybrid_swnuma1_retry_20260515_011856.txt (rows=20, cores=238)
- Compared variants: loaded2, manual sw_numa=1, current(before opt), open_channel force node1, open_channel hybrid clamp

## Effective interval total (40-79)
- loaded2: 16,785,236.25
- manual sw_numa=1: 19,121,245.75
- current(before opt): 26,564,774.30
- open_channel force node1: 27,390,948.55
- open_channel hybrid clamp: 28,025,787.50
- hybrid vs current: 5.50%
- hybrid vs force node1: 2.32%
- hybrid vs manual sw_numa=1: 46.57%

## Global total (all cores)
- loaded2: 22,408,148.35
- manual sw_numa=1: 25,775,818.95
- current(before opt): 50,547,086.15
- open_channel force node1: 36,351,007.30
- open_channel hybrid clamp: 38,870,278.25
- hybrid vs current: -23.10%
- hybrid vs force node1: 6.93%
- hybrid vs manual sw_numa=1: 50.80%

## 40-79 split metrics
- current(before opt): split 40-57 | 58-79, front/back mean 1,123,208.46/288,501.00, ratio 3.89x, shares 76.11%/23.89%
- open_channel force node1: split 40-57 | 58-79, front/back mean 1,131,236.14/319,486.27, ratio 3.54x, shares 74.34%/25.66%
- open_channel hybrid clamp: split 40-57 | 58-79, front/back mean 1,191,312.02/299,189.60, ratio 3.98x, shares 76.51%/23.49%

## p95 hotspots (current vs hybrid)
- current threshold: 1,286,685.86, cores: [0, 3, 6, 8, 10, 12, 26, 27, 46, 48, 51, 80]
- hybrid threshold: 1,158,324.18, cores: [39, 40, 41, 43, 46, 48, 51, 52, 54, 57, 214, 226]
- overlap: 3 / 12
