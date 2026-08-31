# Effective Range Two-Part Analysis (NUMA1: core 40-79)

- Best split point: `57` | `58`
- Part-A (front/high): `40-57`
- Part-B (back/low): `58-79`

## Aggregate (mean per core across samples)
- Part-A average: `1,182,029.17`
- Part-B average: `213,298.62`
- Difference: `968,730.54`
- Ratio A/B: `5.54x`
- Contribution in 40-79: Part-A `81.93%`, Part-B `18.07%`

## Per-sample segment averages
sample_id,front_avg,back_avg,ratio
1,1207428.00,211567.86,5.71
2,1194634.17,213144.41,5.60
3,1191007.11,214000.36,5.57
4,1185167.78,208844.50,5.67
5,1120847.11,219903.00,5.10
6,1184813.44,217492.18,5.45
7,1173392.44,215734.09,5.44
8,1177285.72,211149.59,5.58
9,1176284.78,207999.09,5.66
10,1209431.11,213151.14,5.67
