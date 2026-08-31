# EMON Compare: eq force node1 vs eq online sw_numa

- before(current): emon_hitm_current_redis_bench_20260515_005615.txt (rows=20)
- eq force node1: emon_hitm_eq_force_node1_20260515_014152.txt (rows=20)
- eq online sw_numa: emon_hitm_eq_online_swnuma_retry_20260515_014253.txt (rows=20)

## Effective interval total (40-79)
- before(current): 26,564,774.30
- eq force node1: 27,932,891.95
- eq online sw_numa: 27,277,217.95
- force vs before: 5.15%
- online vs before: 2.68%
- online vs force: -2.35%

## Global total (all cores)
- before(current): 50,547,086.15
- eq force node1: 37,335,900.45
- eq online sw_numa: 37,820,890.50
- force vs before: -26.14%
- online vs before: -25.18%
- online vs force: 1.30%

## Split metrics (40-79)
- before(current): split 40-57 | 58-79, front/back mean 1,123,208.46/288,501.00, ratio 3.89x, shares 76.11%/23.89%
- eq force node1: split 40-57 | 58-79, front/back mean 1,194,928.49/292,008.15, ratio 4.09x, shares 77.00%/23.00%
- eq online sw_numa: split 40-57 | 58-79, front/back mean 1,131,228.18/314,323.21, ratio 3.60x, shares 74.65%/25.35%

## p95 hotspots
- before threshold: 1,286,685.86, cores: [0, 3, 6, 8, 10, 12, 26, 27, 46, 48, 51, 80]
- force threshold: 1,233,006.61, cores: [0, 28, 38, 42, 43, 44, 46, 48, 51, 53, 56, 57]
- online threshold: 1,120,655.25, cores: [0, 31, 39, 40, 44, 46, 48, 49, 50, 52, 53, 56]
