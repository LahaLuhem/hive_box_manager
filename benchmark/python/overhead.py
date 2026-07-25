#!/usr/bin/env python3
"""Derive the wrapper-overhead percentages the top-level README quotes.

Reads ``../results/results_overhead.jsonl`` (façade vs raw hive_ce on the hot paths) and prints
one row per lane: both medians, both minima, the two overhead readings they give, and whether the
lane clears aim #4's under-5% target. Exists so the README's percentages are re-derivable from the
committed data instead of hand-computed once and trusted forever.

Median *and* min, because this lane resolves single-digit percentages and background load on the
host swamps that outright. Min estimates the uncontended cost, so it is the reading that survives a
noisy machine; the median is what a clean run should agree with. When the two disagree by more than
``DIVERGENCE_PCT``, the run was contaminated and no percentage from it means anything. The load
stamp the driver writes is printed alongside for the same reason.

Text only, so this leans on the stdlib rather than the charting stack; run under uv all the same
(see benchmark/README.md).

Maintainer tooling; not shipped (``benchmark/`` is excluded from the pub.dev tarball).
"""

from __future__ import annotations

import json
import statistics
from pathlib import Path

BENCH_DIR = Path(__file__).resolve().parent.parent  # benchmark/
RESULT_FILE = BENCH_DIR / "results" / "results_overhead.jsonl"

TARGET_PCT = 5.0  # aim #4: the façades stay within noise of raw, under 5%
DIVERGENCE_PCT = 10.0  # median-vs-min gap above which the run is contaminated, not noisy

LANES = (
    ("get", "eager", "eager get"),
    ("get", "lazy", "lazy get"),
    ("put", None, "single put"),
)


def load_rows():
    return [
        json.loads(line)
        for line in RESULT_FILE.read_text().splitlines()
        if line.strip()
    ]


def samples(rows, *, mode, box_kind, impl):
    """Every microsecond reading for one (mode, boxKind, impl), in run order."""
    return [
        row["micros"]
        for row in rows
        if row.get("mode") == mode
        and row.get("boxKind") == box_kind
        and row.get("impl") == impl
        and "micros" in row
    ]


def overhead_pct(facade, raw):
    return (facade - raw) / raw * 100


def main():
    rows = load_rows()
    entries = next((row["n"] for row in rows if row.get("mode") == "prep"), None)
    meta = next((row for row in rows if row.get("mode") == "meta"), {})

    print(f"overhead lane: {RESULT_FILE.name}, box prepped with {entries:,} entries")
    if meta:
        print(
            f"reps: {meta.get('reps')}, "
            f"host load {meta.get('loadStart')} -> {meta.get('loadEnd')}"
        )
    else:
        print("no load stamp in this run (predates the driver writing one): treat with suspicion")

    header = (
        f"\n{'lane':<14} {'ops':>7} "
        f"{'facade med':>11} {'raw med':>10} {'by med':>8}   "
        f"{'facade min':>11} {'raw min':>10} {'by min':>8}"
    )
    print(header)
    print("-" * (len(header) - 1))

    verdicts = []
    for mode, box_kind, label in LANES:
        facade = samples(rows, mode=mode, box_kind=box_kind, impl="facade")
        raw = samples(rows, mode=mode, box_kind=box_kind, impl="raw")
        if not facade or not raw:
            print(f"{label:<14} absent from this run")
            continue

        ops = next(
            (
                row.get("ops", row.get("n"))
                for row in rows
                if row.get("mode") == mode and row.get("boxKind") == box_kind
            ),
            None,
        )
        by_median = overhead_pct(statistics.median(facade), statistics.median(raw))
        by_min = overhead_pct(min(facade), min(raw))
        print(
            f"{label:<14} {ops or '-':>7} "
            f"{statistics.median(facade) / 1000:>8.1f} ms {statistics.median(raw) / 1000:>7.1f} ms "
            f"{by_median:>+7.1f}%   "
            f"{min(facade) / 1000:>8.1f} ms {min(raw) / 1000:>7.1f} ms {by_min:>+7.1f}%"
        )
        verdicts.append((label, by_median, by_min, facade + raw))

    print()
    for label, by_median, by_min, all_samples in verdicts:
        spread = max(all_samples) / min(all_samples)
        worst = max(by_median, by_min)
        reading = "median" if by_median >= by_min else "min"
        if abs(by_median - by_min) > DIVERGENCE_PCT:
            print(
                f"  {label}: CONTAMINATED. median says {by_median:+.1f}%, min says {by_min:+.1f}%, "
                f"samples spread {spread:.1f}x. Re-run on a quiet host."
            )
        elif worst >= TARGET_PCT:
            # The stricter of the two readings decides: a claim of "under 5%" that only holds on
            # the friendlier estimator is not a claim, it is a choice of estimator.
            print(
                f"  {label}: OVER the {TARGET_PCT:.0f}% target on the stricter reading "
                f"({worst:+.1f}% by {reading}; {min(by_median, by_min):+.1f}% by the other)."
            )
        else:
            print(
                f"  {label}: within target on both readings "
                f"({by_median:+.1f}% median, {by_min:+.1f}% min, {spread:.1f}x spread)."
            )


if __name__ == "__main__":
    main()
