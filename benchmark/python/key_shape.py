#!/usr/bin/env python3
"""Check the key-shape lane still says what the docs claim it says.

Reads ``../results/results_key_shape.jsonl`` and prints one row per lane, then evaluates the
attribution as a set of explicit relationships rather than leaving a table of numbers for the
reader to interpret. That is the whole point: issue #14's root cause was wrong because someone read
a table and drew the intuitive conclusion from it, and the intuitive conclusion was not the one the
numbers supported.

So each relationship below is stated as a claim and checked. If a future Dart SDK caches the
subtype check this lane depends on, the PREMISE check fails loudly and every doc citing it needs
revisiting, instead of the numbers quietly changing under a paragraph that still asserts the old
story.

Text only, so this leans on the stdlib rather than the charting stack; run under uv all the same
(see benchmark/README.md).

Maintainer tooling; not shipped (``benchmark/`` is excluded from the pub.dev tarball).
"""

from __future__ import annotations

import json
import statistics
from pathlib import Path

BENCH_DIR = Path(__file__).resolve().parent.parent  # benchmark/
RESULT_FILE = BENCH_DIR / "results" / "results_key_shape.jsonl"

BASELINE = "generic-int"

# How close two lanes must be to count as "the same shape". Generous on purpose: the fast lanes sit
# around 13-17 ns where a couple of nanoseconds of scheduling noise is a large fraction, and the
# effect being detected is 20x, not 20%.
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
    return [
        json.loads(line)
        for line in RESULT_FILE.read_text().splitlines()
        if line.strip()
    ]


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
        print("no SDK stamp in this run: re-run before citing it, this lane pins compiler behaviour")

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


if __name__ == "__main__":
    main()
