#!/usr/bin/env python3
"""CWF create-latency vs concurrency chart (single-axis style: avg + p95 lines,
200 ms reference, avg-crossing annotation). Output is written INTO the sweep
result directory by default (same dir as the CSV)."""
import csv, sys, os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

csv_path = sys.argv[1]
# default output = the result directory that holds the CSV
out_png = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
    os.path.dirname(os.path.abspath(csv_path)), "cwf_create_latency_vs_concurrency.png")

rows = list(csv.DictReader(open(csv_path)))
conc = [int(r["concurrency"]) for r in rows]
avg  = [float(r["create_avg_ms"]) for r in rows]
p95  = [float(r["create_p95_ms"]) for r in rows]

# concurrency where the avg line crosses 200 ms (linear interpolation)
TARGET = 200.0
cross_c = None
for i in range(1, len(avg)):
    if (avg[i-1] - TARGET) * (avg[i] - TARGET) <= 0 and avg[i] != avg[i-1]:
        f = (TARGET - avg[i-1]) / (avg[i] - avg[i-1])
        cross_c = conc[i-1] + f * (conc[i] - conc[i-1])
        break

fig, ax = plt.subplots(figsize=(11.0, 5.2), dpi=150)
ax.plot(conc, avg, "o-", color="#1f6fb2", linewidth=2.6, markersize=6,
        label="CWF create-delete avg (ms)", zorder=4)
ax.plot(conc, p95, "^--", color="#9ecae1", linewidth=1.8, markersize=6,
        label="CWF p95 (ms)", zorder=3)
ax.axhline(TARGET, color="#d62728", linewidth=1.6, label="200 ms reference", zorder=2)

if cross_c is not None:
    ax.annotate(f"avg crosses 200 ms\n@ c\u2248{cross_c:.0f}",
                xy=(cross_c, TARGET), xytext=(cross_c + 18, TARGET - 70),
                fontsize=10, color="#b22222", fontweight="bold",
                arrowprops=dict(arrowstyle="->", color="#b22222", lw=1.4))

ax.set_xlabel("# Concurrency of Sandbox creation", fontsize=11)
ax.set_ylabel("Latency (ms)", fontsize=11)
ax.set_xticks(range(100, max(conc) + 1, 20))
ax.set_xlim(min(conc) - 8, max(conc) + 8)
ax.set_ylim(0, max(p95) * 1.12)
ax.grid(True, color="#dddddd", linewidth=0.8, zorder=0)
ax.set_title("CubeSandbox create-delete \u2014 CWF create latency vs concurrency\n"
             "(our reproduction: Xeon 6990E, kernel 7.1.0, BKM limits=500, 100% success)",
             fontsize=12)
ax.legend(loc="upper left", fontsize=10, frameon=True)
fig.tight_layout()
fig.savefig(out_png)
plt.close(fig)
print("avg crosses 200 ms @ c =", None if cross_c is None else round(cross_c, 1))
print("wrote", out_png)
