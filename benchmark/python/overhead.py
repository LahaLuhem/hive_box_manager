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

# Per-op wrapper cost below which a percentage stops being informative. Some ops are so cheap
# (a same-slot get, walking an already-decoded values iterable) that one extra call frame is a
# double-digit percentage while costing tens of nanoseconds. Those lanes get reported in
# nanoseconds, and neither the 5% target nor the divergence check is held against them: the
# percentage swings wildly precisely because its denominator is near zero.
CHEAP_OP_NS = 50.0

# Every lane below has an exact raw hive_ce counterpart, which is what makes a percentage
# meaningful. Grouped reads first, then writes, then the single-value façades.
LANES = (
    ("get", "eager", "get (eager)"),
    ("get", "lazy", "get (lazy)"),
    ("values", "eager", "values (eager)"),
    ("values", "lazy", "values (lazy)"),
    ("contains", "eager", "contains (eager)"),
    ("contains", "lazy", "contains (lazy)"),
    ("put", None, "put"),
    ("putall", None, "putAll"),
    ("delete", None, "delete"),
    ("deleteall", None, "deleteAll"),
    ("single-get", "eager", "single get (eager)"),
    ("single-get", "lazy", "single get (lazy)"),
    ("single-set", "eager", "single set (eager)"),
    ("single-set", "lazy", "single set (lazy)"),
)


def load_rows():
    return [json.loads(line) for line in RESULT_FILE.read_text().splitlines() if line.strip()]


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
    prepped = sorted({row["n"] for row in rows if row.get("mode") == "prep"})
    meta = next((row for row in rows if row.get("mode") == "meta"), {})

    print(f"overhead lane: {RESULT_FILE.name}")
    print(f"boxes prepped with {', '.join(f'{n:,}' for n in prepped)} entries")
    if meta:
        print(
            f"reps: {meta.get('reps')}, host load {meta.get('loadStart')} -> {meta.get('loadEnd')}"
        )
    else:
        print("no load stamp in this run (predates the driver writing one): treat with suspicion")

    header = (
        f"\n{'lane':<20} {'ops':>7} "
        f"{'facade med':>11} {'raw med':>10} {'by med':>8} {'by min':>8} {'per op':>10}"
    )
    print(header)
    print("-" * (len(header) - 1))

    verdicts = []
    for mode, box_kind, label in LANES:
        facade = samples(rows, mode=mode, box_kind=box_kind, impl="facade")
        raw = samples(rows, mode=mode, box_kind=box_kind, impl="raw")
        if not facade or not raw:
            print(f"{label:<20} absent from this run")
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
        # Nanoseconds of wrapper per op: the reading that stays interpretable when the underlying
        # op is so cheap that a percentage is mostly a statement about the denominator.
        per_op_ns = (
            (statistics.median(facade) - statistics.median(raw)) * 1000 / ops if ops else None
        )
        print(
            f"{label:<20} {ops or '-':>7} "
            f"{statistics.median(facade) / 1000:>8.1f} ms {statistics.median(raw) / 1000:>7.1f} ms "
            f"{by_median:>+7.1f}% {by_min:>+7.1f}% "
            f"{f'{per_op_ns:+.0f} ns' if per_op_ns is not None else '-':>10}"
        )
        verdicts.append((label, by_median, by_min, facade + raw, per_op_ns))

    print()
    for label, by_median, by_min, all_samples, per_op_ns in verdicts:
        spread = max(all_samples) / min(all_samples)
        worst = max(by_median, by_min)
        reading = "median" if by_median >= by_min else "min"
        cheap = per_op_ns is not None and abs(per_op_ns) < CHEAP_OP_NS
        if abs(by_median - by_min) > DIVERGENCE_PCT and not cheap:
            print(
                f"  {label}: CONTAMINATED. median says {by_median:+.1f}%, min says {by_min:+.1f}%, "
                f"samples spread {spread:.1f}x. Re-run on a quiet host."
            )
        elif worst >= TARGET_PCT and cheap:
            # A large percentage over a tiny per-op delta is a fact about the denominator, not a
            # performance problem: the underlying op is so cheap that any wrapper frame at all
            # doubles it. Quote the nanoseconds for these, never the percentage.
            print(
                f"  {label}: {worst:+.1f}% but only {per_op_ns:+.0f} ns per op. The raw op is too "
                f"cheap for a percentage to mean anything here; quote the nanoseconds."
            )
        elif worst >= TARGET_PCT:
            # The stricter of the two readings decides: a claim of "under 5%" that only holds on
            # the friendlier estimator is not a claim, it is a choice of estimator.
            print(
                f"  {label}: OVER the {TARGET_PCT:.0f}% target on the stricter reading "
                f"({worst:+.1f}% by {reading}; {min(by_median, by_min):+.1f}% by the other), "
                f"{per_op_ns:+.0f} ns per op."
            )
        else:
            print(
                f"  {label}: within target on both readings "
                f"({by_median:+.1f}% median, {by_min:+.1f}% min, {spread:.1f}x spread)."
            )


if __name__ == "__main__":
    main()
