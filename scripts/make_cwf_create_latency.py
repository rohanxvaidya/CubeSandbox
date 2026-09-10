#!/usr/bin/env python3
"""Create-latency-vs-concurrency diagram for one CWF sweep dir (house style)."""
import csv, os, sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

D = sys.argv[1] if len(sys.argv) > 1 else "/data/cwf-sweep-createdelete-20260910-105859"
CONFIG = sys.argv[2] if len(sys.argv) > 2 else "refmatch-1orch_n-c10"
csv_path = os.path.join(D, "cwf_sweep_createdelete.csv")

c, avg, p95 = [], [], []
with open(csv_path) as f:
    for r in csv.DictReader(f):
        c.append(float(r["concurrency"])); avg.append(float(r["create_avg_ms"])); p95.append(float(r["create_p95_ms"]))

def crossing(x, y, thr=200.0):
    for i in range(1, len(y)):
        if y[i-1] < thr <= y[i]:
            t = (thr - y[i-1]) / (y[i] - y[i-1]); return x[i-1] + t*(x[i]-x[i-1])
    return None
knee = crossing(c, avg)

fig, ax = plt.subplots(figsize=(13.5, 6.5))
ax.plot(c, avg, "-o", color="#1f4e9c", lw=2, ms=5, label="CWF create-delete avg (ms)")
ax.plot(c, p95, "--", color="#7fa8d8", lw=1.5, label="p95 (ms)")
ax.axhline(200, color="red", lw=2, label="200 ms reference")
if knee:
    ax.annotate(f"avg crosses 200 ms\n@ c\u2248{knee:.0f}", xy=(knee, 200), xytext=(knee+8, 430),
                color="#7a1a1a", fontsize=11, fontweight="bold",
                arrowprops=dict(arrowstyle="->", color="#7a1a1a", lw=1.5))
ax.set_xlabel("# Concurrency of Sandbox creation"); ax.set_ylabel("Latency (ms)")
ax.set_title("CubeSandbox create-delete \u2014 CWF create latency vs concurrency\n"
             f"({CONFIG}: Xeon 6990E, kernel 7.1.0-mzgit, egress in-path, BKM limits=500, 100% success)")
ax.set_ylim(0, 500); ax.grid(True, alpha=0.3); ax.legend(loc="upper left", fontsize=10)
fig.tight_layout()
out = os.path.join(D, f"cwf_create_latency_vs_concurrency_{CONFIG}.png")
fig.savefig(out, dpi=110); plt.close(fig)
print("saved:", out, "| knee c\u2248%.0f" % knee if knee else "no crossing")
