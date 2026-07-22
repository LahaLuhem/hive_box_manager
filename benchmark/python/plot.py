#!/usr/bin/env python3
"""Render the benchmark charts (PNG) from the committed JSONL results.

seaborn (whitegrid theme) over matplotlib, fed polars frames via seaborn's dataframe
interchange support (0.13+), matching the sibling packages' chart house style; run under uv
(see benchmark/README.md). Reads ``../results/*.jsonl``, takes per-config medians, and writes
``../reports/*.png``.

Maintainer tooling; not shipped (``benchmark/`` is excluded from the pub.dev
tarball, so none of this reaches downstream users).

Palette: the Okabe-Ito CVD-safe pair (blue #0072B2, vermillion #D55E00),
validated with the dataviz skill's checker. The sibling's "Set2" fails that
checker (chroma floor + contrast), so it isn't reused here. Series also differ
by dash pattern and marker, so identity never rests on colour alone.
"""

from __future__ import annotations

import json
import statistics
from collections import defaultdict
from pathlib import Path

import matplotlib.pyplot as plt
import polars as pl
import seaborn as sns

BENCH_DIR = Path(__file__).resolve().parent.parent  # benchmark/
RESULT_FILES = (
    BENCH_DIR / "results" / "results_aot.jsonl",
    BENCH_DIR / "results" / "results_1m.jsonl",
)
OUT_DIR = BENCH_DIR / "reports"

BLUE = "#0072B2"  # series A: packed-int / eager
VERMILLION = "#D55E00"  # series B: String composite / lazy
PALETTE = [BLUE, VERMILLION]
MARKERS = ["o", "s"]
DASHES = ["", (4, 2)]  # solid, then dashed
INK = "#222222"  # text + annotations (a text token, never a series colour)

CHART_DPI = 150  # matches the sibling; sharp on retina without bloating the PNG
FIG_SIZE = (8.0, 4.6)


def load_rows():
    rows = []
    for path in RESULT_FILES:
        for line in path.read_text().splitlines():
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def median_by_size(rows, *, mode, key_kind, box_kind, field="ms"):
    """{n: median(field)} across reps for one (mode, key_kind, box_kind)."""
    buckets = defaultdict(list)
    for row in rows:
        if (
            row.get("mode") == mode
            and row.get("keyKind") == key_kind
            and row.get("boxKind") == box_kind
            and row.get("n") is not None
            and field in row
        ):
            buckets[row["n"]].append(row[field])

    return {n: statistics.median(values) for n, values in buckets.items()}


def median_per_op_us(rows, *, key_kind, box_kind):
    """{n: median microseconds-per-op} for reads (ms / ops * 1000)."""
    buckets = defaultdict(list)
    for row in rows:
        if (
            row.get("mode") == "get"
            and row.get("keyKind") == key_kind
            and row.get("boxKind") == box_kind
            and row.get("ops")
        ):
            buckets[row["n"]].append(row["ms"] / row["ops"] * 1000)

    return {n: statistics.median(values) for n, values in buckets.items()}


def size_label(n):
    return {1_000: "1K", 10_000: "10K", 100_000: "100K", 1_000_000: "1M"}.get(n, str(n))


def _tidy(series_map):
    records = [
        {"n": n, "value": value, "series": name}
        for name, points in series_map.items()
        for n, value in points.items()
    ]

    return pl.DataFrame(records)


def render(series_map, *, order, title, xlabel, ylabel, out_name, log_y=False, annotate=None):
    frame = _tidy(series_map)
    fig, ax = plt.subplots(figsize=FIG_SIZE)

    sns.lineplot(
        data=frame,
        x="n",
        y="value",
        hue="series",
        style="series",
        hue_order=order,
        style_order=order,
        palette=PALETTE,
        markers=MARKERS,
        dashes=DASHES,
        ax=ax,
    )

    ax.set_xscale("log")
    if log_y:
        ax.set_yscale("log")
    sizes = sorted(frame["n"].unique().to_list())
    ax.set_xticks(sizes)
    ax.set_xticklabels([size_label(n) for n in sizes])
    ax.set_title(title, fontweight="bold", color=INK, pad=12)
    ax.set_xlabel(xlabel, color=INK)
    ax.set_ylabel(ylabel, color=INK)
    ax.legend(title=None, frameon=False)

    for name, (formatter, dy) in (annotate or {}).items():
        points = series_map[name]
        n = max(points)
        ax.annotate(
            formatter(points[n]),
            (n, points[n]),
            textcoords="offset points",
            xytext=(0, dy),
            ha="right",
            color=INK,
            fontsize=9,
        )

    fig.tight_layout()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    fig.savefig(OUT_DIR / out_name, dpi=CHART_DPI)
    plt.close(fig)
    print(f"wrote reports/{out_name}")


def main():
    sns.set_theme(
        style="whitegrid",
        context="notebook",
        palette=PALETTE,
        rc={
            "lines.linewidth": 2,
            "lines.markersize": 8,
            "lines.markeredgecolor": "white",
            "lines.markeredgewidth": 1.0,
        },
    )
    rows = load_rows()

    render(
        {
            "packed int": median_by_size(rows, mode="get", key_kind="arith", box_kind="eager"),
            "String composite": median_by_size(
                rows, mode="get", key_kind="string", box_kind="eager"
            ),
        },
        order=["packed int", "String composite"],
        title="Eager get: packed-int vs String key",
        xlabel="entries in the box",
        ylabel="time for a full pass of reads (ms)",
        out_name="codec_get_scaling.png",
        annotate={
            "packed int": (lambda v: f"{v:.0f} ms", 8),
            "String composite": (lambda v: f"{v:.0f} ms", 8),
        },
    )

    render(
        {
            "packed int": {
                n: b / 1e6
                for n, b in median_by_size(
                    rows, mode="open", key_kind="arith", box_kind="eager", field="rssDeltaBytes"
                ).items()
            },
            "String composite": {
                n: b / 1e6
                for n, b in median_by_size(
                    rows, mode="open", key_kind="string", box_kind="eager", field="rssDeltaBytes"
                ).items()
            },
        },
        order=["packed int", "String composite"],
        title="Keystore RAM after open: packed-int vs String key",
        xlabel="entries in the box",
        ylabel="RSS delta after open (MB)",
        out_name="codec_rss_scaling.png",
        annotate={
            "packed int": (lambda v: f"{v:.0f} MB", 8),
            "String composite": (lambda v: f"{v:.0f} MB", 8),
        },
    )

    render(
        {
            "eager": median_by_size(rows, mode="open", key_kind="arith", box_kind="eager"),
            "lazy": median_by_size(rows, mode="open", key_kind="arith", box_kind="lazy"),
        },
        order=["eager", "lazy"],
        title="Box open time: eager vs lazy",
        xlabel="entries in the box",
        ylabel="open time (ms)",
        out_name="open_eager_vs_lazy.png",
        log_y=True,
    )

    render(
        {
            "eager (from memory)": median_per_op_us(rows, key_kind="arith", box_kind="eager"),
            "lazy (from disk)": median_per_op_us(rows, key_kind="arith", box_kind="lazy"),
        },
        order=["eager (from memory)", "lazy (from disk)"],
        title="Read latency per op: eager vs lazy",
        xlabel="entries in the box",
        ylabel="time per read (µs, log scale)",
        out_name="read_eager_vs_lazy.png",
        log_y=True,
        annotate={
            "eager (from memory)": (lambda v: f"{v:.1f} µs", -14),
            "lazy (from disk)": (lambda v: f"{v:.0f} µs", 8),
        },
    )


if __name__ == "__main__":
    main()
