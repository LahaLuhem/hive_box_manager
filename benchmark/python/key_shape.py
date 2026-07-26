#!/usr/bin/env python3
"""Check the key-shape lane still says what the docs claim it says.

Reads ``../results/results_key_shape.jsonl``, prints one row per lane, then checks the attribution
as explicit claims rather than leaving a table for the reader to interpret. That is the point:
issue #14's root cause was wrong because someone read a table and drew the intuitive conclusion,
which was not the one the numbers supported. If a future SDK caches the subtype check, PREMISE
fails loudly instead of the numbers quietly changing under docs that still assert the old story.

Also writes ``../reports/key_shape_attribution.png``: the same argument as a chart, because the
original mistake was made reading a table, and a table is what reproduces it. seaborn/matplotlib
house style and the Okabe-Ito palette, as in plot.py; run under uv (see benchmark/README.md).

Maintainer tooling; not shipped (``benchmark/`` is excluded from the pub.dev tarball).
"""

from __future__ import annotations

import json
import statistics
from pathlib import Path

import matplotlib.pyplot as plt
import seaborn as sns

BENCH_DIR = Path(__file__).resolve().parent.parent  # benchmark/
RESULT_FILE = BENCH_DIR / "results" / "results_key_shape.jsonl"

BASELINE = "generic-int"

OUT_DIR = BENCH_DIR / "reports"
CHART_NAME = "key_shape_attribution.png"

BLUE = "#0072B2"  # free: the shapes that cost nothing
VERMILLION = "#D55E00"  # costly: the shapes that pay the subtype check
INK = "#222222"
CHART_DPI = 150
FIG_SIZE = (9.0, 5.4)

# Above this multiple of the baseline a lane is drawn as costly. The gap is 20x, so the exact
# threshold is irrelevant; it exists so the colouring is derived rather than hard-coded per lane.
COSTLY_MULTIPLE = 5.0

# The two annotations that carry the argument, keyed by the lane they point at.
PAIR_NOTES = {
    "raw-generic-adapter": "engine's key type parameter gone: no change",
    "raw-concrete-adapter": "class type parameters gone too: free",
}

# How close two lanes must be to count as "the same shape". Generous: the fast lanes sit at 13-17 ns
# where a nanosecond of noise is a large fraction, and the effect being detected is 20x, not 20%.
NEAR_TOL = 0.35

# The defect has to still be here for anything else in this file to mean something.
PREMISE_MULTIPLE = 5.0

LANE_ORDER = (
    "generic-int",
    "generic-string",
    "generic-record",
    "raw-generic-adapter",
    "raw-concrete-adapter",
    "raw-widened-adapter",
    "raw-object-record",
    "raw-direct",
)

# (lane, reference, claim). Each one moves a single variable against its reference.
CLAIMS = (
    (
        "generic-string",
        "generic-int",
        "a non-record generic is free, so 'generics are slow' is not the explanation",
    ),
    (
        "raw-generic-adapter",
        "generic-record",
        "the engine's key type parameter is not the cost: removing it changes nothing",
    ),
    (
        "raw-concrete-adapter",
        "generic-int",
        "a concrete record parameter is free, so the generic record parameter is the whole cost",
    ),
    (
        "raw-widened-adapter",
        "generic-record",
        "widening the parameter to Object does not help: the check relocates, it does not vanish",
    ),
    (
        "raw-object-record",
        "generic-int",
        "a concrete (Object, Object) parameter is free, and is the trap: it hides the cost while "
        "keeping a record on the boundary",
    ),
    (
        "raw-direct",
        "generic-int",
        "two scalar arguments cost nothing: the shipped shape",
    ),
)


def load_rows():
    return [json.loads(line) for line in RESULT_FILE.read_text().splitlines() if line.strip()]


def samples(rows, lane):
    """Every ns/op reading for one lane, in run order."""
    return [row["nsPerOp"] for row in rows if row.get("lane") == lane and "nsPerOp" in row]


def main():
    rows = load_rows()
    meta = next((row for row in rows if row.get("mode") == "meta"), {})
    sdks = {row["sdk"] for row in rows if "sdk" in row}

    print(f"key-shape lane: {RESULT_FILE.name}")
    if meta:
        print(
            f"reps: {meta.get('reps')}, n: {meta.get('n'):,}, "
            f"host load {meta.get('loadStart')} -> {meta.get('loadEnd')}"
        )
    if sdks:
        for sdk in sorted(sdks):
            print(f"sdk: {sdk}")
    else:
        print(
            "no SDK stamp in this run: re-run before citing it, this lane pins compiler behaviour"
        )

    by_lane = {lane: samples(rows, lane) for lane in LANE_ORDER}
    missing = [lane for lane, values in by_lane.items() if not values]
    if missing:
        print(f"\nlanes absent from this run: {', '.join(missing)}")

    base = statistics.median(by_lane[BASELINE]) if by_lane.get(BASELINE) else None
    if base is None:
        print(f"\nno {BASELINE} lane: nothing to compare against")
        return

    header = f"\n{'lane':<24} {'med ns':>8} {'min ns':>8} {'vs base':>9} {'delta':>9} {'spread':>8}"
    print(header)
    print("-" * (len(header) - 1))
    for lane in LANE_ORDER:
        values = by_lane[lane]
        if not values:
            continue
        med = statistics.median(values)
        print(
            f"{lane:<24} {med:>8.1f} {min(values):>8.1f} {med / base:>8.2f}x "
            f"{med - base:>+8.1f} {max(values) - min(values):>7.1f}"
        )

    print()
    record = by_lane.get("generic-record")
    if record:
        multiple = statistics.median(record) / base
        if multiple < PREMISE_MULTIPLE:
            print(
                f"  PREMISE FAILED: generic-record is only {multiple:.1f}x the baseline. This SDK "
                f"no longer pays the record subtype check the way it did at {multiple:.1f}x < "
                f"{PREMISE_MULTIPLE:.0f}x. Every doc citing this lane needs revisiting."
            )
        else:
            print(f"  premise holds: generic-record is {multiple:.1f}x the baseline on this SDK.")

    for lane, reference, claim in CLAIMS:
        values, reference_values = by_lane.get(lane), by_lane.get(reference)
        if not values or not reference_values:
            continue
        ratio = statistics.median(values) / statistics.median(reference_values)
        if abs(ratio - 1.0) <= NEAR_TOL:
            print(f"  HOLDS  {lane} ~= {reference} ({ratio:.2f}x): {claim}")
        else:
            print(
                f"  BROKEN {lane} is {ratio:.2f}x {reference}, expected ~1.00x. "
                f"This claim no longer holds: {claim}"
            )

    render_chart(by_lane, base)


def render_chart(by_lane, base):
    """Draw the lanes in declaration order, so reading top to bottom *is* the argument."""
    lanes = [lane for lane in LANE_ORDER if by_lane.get(lane)]
    values = [statistics.median(by_lane[lane]) for lane in lanes]
    widest = max(values)
    costly = [v / base >= COSTLY_MULTIPLE for v in values]

    # The pair notes ride on the tick labels rather than as arrows into the plot: the reader is
    # already looking at the lane name, and arrows across bars this uneven collide with everything.
    labels = [f"{lane}\n{PAIR_NOTES[lane]}" if lane in PAIR_NOTES else lane for lane in lanes]

    sns.set_theme(style="whitegrid")
    fig, ax = plt.subplots(figsize=FIG_SIZE, layout="constrained")
    bars = ax.barh(
        labels,
        values,
        color=[VERMILLION if c else BLUE for c in costly],
        edgecolor=INK,
        linewidth=0.6,
    )
    # Hatching so the two groups survive greyscale and colour blindness (plot.py's rule; bars
    # cannot carry the dash/marker cues the line charts use).
    for bar, is_costly in zip(bars, costly, strict=True):
        if is_costly:
            bar.set_hatch("///")

    for bar, value in zip(bars, values, strict=True):
        ax.text(
            bar.get_width() + widest * 0.015,
            bar.get_y() + bar.get_height() / 2,
            f"{value:.0f} ns",
            va="center",
            fontsize=9,
            color=INK,
        )

    ax.invert_yaxis()
    ax.set_xlabel("ns per op (AOT, median)")
    ax.set_xlim(0, widest * 1.16)
    ax.tick_params(axis="y", labelsize=9)
    # suptitle + set_title rather than a hand-placed text: constrained layout then spaces the two
    # for us, instead of the subtitle colliding with the title's descenders at some figure sizes.
    fig.suptitle(
        "What the dual-key overhead actually was",
        x=0.012,
        ha="left",
        fontsize=12,
        color=INK,
    )
    ax.set_title(
        "Each lane changes one thing from the lane above it. Only the shapes with a record\n"
        "built from the class's own type parameters pay.",
        loc="left",
        fontsize=8.5,
        color=INK,
        linespacing=1.5,
        pad=10,
    )
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    fig.savefig(OUT_DIR / CHART_NAME, dpi=CHART_DPI)
    plt.close(fig)
    print(f"\nwrote reports/{CHART_NAME}")


if __name__ == "__main__":
    main()
