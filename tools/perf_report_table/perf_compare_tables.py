#!/usr/bin/env python3
"""Build comparison tables from perf report/hotspots text outputs.

Examples:
  python3 perf_compare_tables.py \
    --type report \
    --input snc0=snc0-default-redis_report.txt \
    --input snc1-default=snc1-default-redis-irq-snc1_report.txt \
    --input snc1-opt=snc1-opt-redis-irq-snc1_report.txt \
    --out-md report_compare.md --out-csv report_compare.csv

  python3 perf_compare_tables.py \
    --type hotspots \
    --input snc0=snc0-default-redis_hotspots.txt \
    --input snc1-default=snc1-default-redis-irq-snc1_hotspots.txt \
    --input snc1-opt=snc1-opt-redis-irq-snc1_hotspots.txt \
    --out-md hotspots_compare.md --out-csv hotspots_compare.csv

    # One-click mode: discover both *_report.txt and *_hotspots.txt by prefix,
    # then generate 4 files with one command.
    python3 perf_compare_tables.py \
        --auto-pair \
        --batch-dir . \
        --out-prefix auto_compare
"""

from __future__ import annotations

import argparse
import csv
import glob
import os
import re
from collections import OrderedDict
from typing import Dict, Iterable, List, Tuple


REPORT_LINE_RE = re.compile(
    r"^\s*(?P<pct>[0-9]+\.[0-9]+)%\s+[0-9]+\.[0-9]+%\s+[0-9,]+\s+(?P<metric>.+?)\s*$"
)
HOTSPOTS_LINE_RE = re.compile(
    r"^\s*(?P<pct>[0-9]+\.[0-9]+)%\s+[0-9,]+\s+\S+\s+\S+\s+\S+\s+(?P<metric>.+?)\s*$"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare per-metric percentages across perf report/hotspots txt files."
    )
    parser.add_argument(
        "--type",
        choices=["report", "hotspots"],
        help="Input file type to parse.",
    )
    parser.add_argument(
        "--input",
        action="append",
        metavar="LABEL=FILE",
        help="One config input mapping, can be used multiple times.",
    )
    parser.add_argument(
        "--out-md",
        default="",
        help="Write markdown table to this file path.",
    )
    parser.add_argument(
        "--out-csv",
        default="",
        help="Write csv table to this file path.",
    )
    parser.add_argument(
        "--sort",
        choices=["metric", "max", "first"],
        default="max",
        help="Row sort: by metric name, max value across columns, or first column value.",
    )
    parser.add_argument(
        "--precision",
        type=int,
        default=2,
        help="Decimal digits for displayed percentages.",
    )
    parser.add_argument(
        "--stdout",
        action="store_true",
        help="Print markdown table to stdout.",
    )
    parser.add_argument(
        "--auto-pair",
        action="store_true",
        help="Auto-discover paired *_report.txt and *_hotspots.txt files and run both comparisons.",
    )
    parser.add_argument(
        "--batch-dir",
        default=".",
        help="Directory to scan when --auto-pair is enabled.",
    )
    parser.add_argument(
        "--report-suffix",
        default="_report.txt",
        help="Report file suffix used in --auto-pair mode.",
    )
    parser.add_argument(
        "--hotspots-suffix",
        default="_hotspots.txt",
        help="Hotspots file suffix used in --auto-pair mode.",
    )
    parser.add_argument(
        "--out-prefix",
        default="compare",
        help="Output prefix for --auto-pair mode. Files: <prefix>_report.md/.csv and <prefix>_hotspots.md/.csv",
    )
    return parser.parse_args()


def parse_inputs(raw_inputs: Iterable[str]) -> OrderedDict[str, str]:
    pairs: OrderedDict[str, str] = OrderedDict()
    for raw in raw_inputs:
        if "=" not in raw:
            raise ValueError(f"Invalid --input '{raw}', expected LABEL=FILE")
        label, path = raw.split("=", 1)
        label = label.strip()
        path = path.strip()
        if not label or not path:
            raise ValueError(f"Invalid --input '{raw}', expected LABEL=FILE")
        if label in pairs:
            raise ValueError(f"Duplicate label '{label}'")
        if not os.path.isfile(path):
            raise FileNotFoundError(f"Input file not found: {path}")
        pairs[label] = path
    if len(pairs) < 2:
        raise ValueError("At least 2 --input items are required for comparison")
    return pairs


def discover_paired_inputs(
    batch_dir: str, report_suffix: str, hotspots_suffix: str
) -> Tuple[OrderedDict[str, str], OrderedDict[str, str]]:
    if not os.path.isdir(batch_dir):
        raise FileNotFoundError(f"Batch directory not found: {batch_dir}")

    report_files = glob.glob(os.path.join(batch_dir, f"*{report_suffix}"))
    hotspots_files = glob.glob(os.path.join(batch_dir, f"*{hotspots_suffix}"))

    report_map = {}
    for path in report_files:
        name = os.path.basename(path)
        if not name.endswith(report_suffix):
            continue
        prefix = name[: -len(report_suffix)]
        report_map[prefix] = path

    hotspots_map = {}
    for path in hotspots_files:
        name = os.path.basename(path)
        if not name.endswith(hotspots_suffix):
            continue
        prefix = name[: -len(hotspots_suffix)]
        hotspots_map[prefix] = path

    common_prefixes = sorted(set(report_map) & set(hotspots_map))
    if len(common_prefixes) < 2:
        raise ValueError(
            "Need at least 2 paired prefixes for comparison in --auto-pair mode"
        )

    report_inputs: OrderedDict[str, str] = OrderedDict()
    hotspots_inputs: OrderedDict[str, str] = OrderedDict()
    for prefix in common_prefixes:
        report_inputs[prefix] = report_map[prefix]
        hotspots_inputs[prefix] = hotspots_map[prefix]

    return report_inputs, hotspots_inputs


def parse_file(path: str, file_type: str) -> Dict[str, float]:
    line_re = REPORT_LINE_RE if file_type == "report" else HOTSPOTS_LINE_RE
    values: Dict[str, float] = {}
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            m = line_re.match(line)
            if not m:
                continue
            pct = float(m.group("pct"))
            metric = m.group("metric").strip()
            values[metric] = pct
    return values


def build_matrix(
    inputs: OrderedDict[str, str], file_type: str
) -> Tuple[List[str], List[List[float]], List[str]]:
    labels = list(inputs.keys())
    parsed: Dict[str, Dict[str, float]] = {
        label: parse_file(path, file_type) for label, path in inputs.items()
    }

    metric_order: List[str] = []
    seen = set()
    for label in labels:
        for metric in parsed[label]:
            if metric not in seen:
                seen.add(metric)
                metric_order.append(metric)

    rows: List[List[float]] = []
    for metric in metric_order:
        row = [parsed[label].get(metric, 0.0) for label in labels]
        rows.append(row)

    return labels, rows, metric_order


def sort_rows(
    metrics: List[str], rows: List[List[float]], sort_mode: str
) -> Tuple[List[str], List[List[float]]]:
    paired = list(zip(metrics, rows))
    if sort_mode == "metric":
        paired.sort(key=lambda x: x[0])
    elif sort_mode == "first":
        paired.sort(key=lambda x: x[1][0], reverse=True)
    else:
        paired.sort(key=lambda x: max(x[1]), reverse=True)
    sorted_metrics = [p[0] for p in paired]
    sorted_rows = [p[1] for p in paired]
    return sorted_metrics, sorted_rows


def to_markdown(
    title: str, metric_header: str, labels: List[str], metrics: List[str], rows: List[List[float]], precision: int
) -> str:
    header = [metric_header] + labels
    sep = ["---"] + ["---:" for _ in labels]
    out = [f"# {title}", "", f"| {' | '.join(header)} |", f"| {' | '.join(sep)} |"]
    fmt = f"{{:.{precision}f}}"
    for metric, row in zip(metrics, rows):
        nums = [fmt.format(v) for v in row]
        out.append(f"| {metric} | {' | '.join(nums)} |")
    out.append("")
    return "\n".join(out)


def write_csv(path: str, metric_header: str, labels: List[str], metrics: List[str], rows: List[List[float]], precision: int) -> None:
    fmt = f"{{:.{precision}f}}"
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow([metric_header] + labels)
        for metric, row in zip(metrics, rows):
            w.writerow([metric] + [fmt.format(v) for v in row])


def run_single_compare(
    file_type: str,
    inputs: OrderedDict[str, str],
    sort_mode: str,
    precision: int,
) -> str:
    labels, rows, metrics = build_matrix(inputs, file_type)
    metrics, rows = sort_rows(metrics, rows, sort_mode)

    metric_header = "指标(Shared Object)" if file_type == "report" else "指标(Symbol)"
    title = f"{file_type}.txt 指标比重对比"
    return to_markdown(title, metric_header, labels, metrics, rows, precision)


def main() -> int:
    args = parse_args()
    if args.auto_pair:
        try:
            report_inputs, hotspots_inputs = discover_paired_inputs(
                args.batch_dir, args.report_suffix, args.hotspots_suffix
            )
        except (ValueError, FileNotFoundError) as e:
            raise SystemExit(str(e))

        for file_type, inputs in (("report", report_inputs), ("hotspots", hotspots_inputs)):
            labels, rows, metrics = build_matrix(inputs, file_type)
            metrics, rows = sort_rows(metrics, rows, args.sort)
            metric_header = (
                "指标(Shared Object)" if file_type == "report" else "指标(Symbol)"
            )
            title = f"{file_type}.txt 指标比重对比"
            md = to_markdown(title, metric_header, labels, metrics, rows, args.precision)

            out_md = f"{args.out_prefix}_{file_type}.md"
            out_csv = f"{args.out_prefix}_{file_type}.csv"
            with open(out_md, "w", encoding="utf-8") as f:
                f.write(md)
            write_csv(out_csv, metric_header, labels, metrics, rows, args.precision)

            if args.stdout:
                print(md)
        return 0

    if not args.type:
        raise SystemExit("--type is required when --auto-pair is not used")
    if not args.input:
        raise SystemExit("--input is required when --auto-pair is not used")

    try:
        inputs = parse_inputs(args.input)
    except (ValueError, FileNotFoundError) as e:
        raise SystemExit(str(e))

    labels, rows, metrics = build_matrix(inputs, args.type)
    metrics, rows = sort_rows(metrics, rows, args.sort)

    metric_header = "指标(Shared Object)" if args.type == "report" else "指标(Symbol)"
    title = f"{args.type}.txt 指标比重对比"
    md = to_markdown(title, metric_header, labels, metrics, rows, args.precision)

    wrote = False
    if args.out_md:
        with open(args.out_md, "w", encoding="utf-8") as f:
            f.write(md)
        wrote = True
    if args.out_csv:
        write_csv(args.out_csv, metric_header, labels, metrics, rows, args.precision)
        wrote = True
    if args.stdout or not wrote:
        print(md)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
