#!/usr/bin/env python3
"""Summarise the list-box lane: `ListBox` against the two hand-rolled baselines.

Reads ``../results/results_list_box.jsonl`` and prints, per element type and elements-per-key, the
median time for each impl plus two ratios that answer different questions:

* **vs correct** is the wrapper tax. `correct` is the code a consumer writes once they know
  about the reification trap (a `.cast<T>()` on read, a defensive `List.of` on write), so this
  ratio prices the façade against a competent hand-roll.
* **vs naive** prices *safety*. `naive` skips both, and on the ``obj`` axis it cannot read data a
  previous process wrote at all: those cells print FAILS, which is the whole argument for the box.

A per-element nanosecond column comes along because these costs scale with list length, so a single
percentage would hide which axis it moved on.

Text only, so this leans on the stdlib rather than the charting stack; run under uv all the same
(see benchmark/README.md).

Maintainer tooling; not shipped (``benchmark/`` is excluded from the pub.dev tarball).
"""

from __future__ import annotations

import json
import statistics
from pathlib import Path

BENCH_DIR = Path(__file__).resolve().parent.parent  # benchmark/
RESULT_FILE = BENCH_DIR / "results" / "results_list_box.jsonl"

IMPLS = ("naive", "correct", "facade")
MODES = ("get", "put", "putall", "add", "remove", "open")
ELEMS = (
    ("str", "List<String> (primitive elements)"),
    ("obj", "List<Person> (custom adapter type)"),
)


def load_rows():
    return [json.loads(line) for line in RESULT_FILE.read_text().splitlines() if line.strip()]


def cell(rows, *, mode, impl, elem, list_len):
    """Median micros for one cell, plus whether that impl failed outright."""
    matching = [
        row
        for row in rows
        if row.get("mode") == mode
        and row.get("impl") == impl
        and row.get("elem") == elem
        and row.get("listLen") == list_len
    ]
    if not matching:
        return None, False

    failed = any(row.get("failure") for row in matching)

    return statistics.median(row["micros"] for row in matching), failed


def ratio(facade, other):
    if facade is None or other is None or not other:
        return "-"

    return f"{facade / other:.2f}x"


def main():
    rows = load_rows()
    meta = next((row for row in rows if row.get("mode") == "meta"), {})
    list_lens = sorted({row["listLen"] for row in rows if row.get("mode") == "get"})

    print(f"list-box lane: {RESULT_FILE.name}")
    print(f"keys per box: {meta.get('keys')}, reps: {meta.get('reps')}")
    print(f"host load {meta.get('loadStart')} -> {meta.get('loadEnd')}")

    for elem, title in ELEMS:
        print(f"\n=== {title} ===")
        header = (
            f"{'mode':<8} {'len':>5} {'naive':>10} {'correct':>10} {'facade':>10} "
            f"{'vs correct':>11} {'vs naive':>10} {'per element':>12}"
        )
        print(header)
        print("-" * len(header))

        for mode in MODES:
            for list_len in list_lens:
                naive, naive_failed = cell(
                    rows, mode=mode, impl="naive", elem=elem, list_len=list_len
                )
                correct, _ = cell(rows, mode=mode, impl="correct", elem=elem, list_len=list_len)
                facade, _ = cell(rows, mode=mode, impl="facade", elem=elem, list_len=list_len)
                if facade is None:
                    continue

                naive_cell = "FAILS" if naive_failed else f"{naive / 1000:.2f} ms"
                # A failed impl has no meaningful duration, so its ratio is suppressed rather than
                # computed against a number that only measures how fast it threw.
                vs_naive = "n/a" if naive_failed else ratio(facade, naive)
                per_element = (
                    f"{(facade - correct) * 1000 / (meta.get('keys', 1) * list_len):+.0f} ns"
                    if correct is not None
                    else "-"
                )
                print(
                    f"{mode:<8} {list_len:>5} {naive_cell:>10} "
                    f"{correct / 1000:>7.2f} ms {facade / 1000:>7.2f} ms "
                    f"{ratio(facade, correct):>11} {vs_naive:>10} {per_element:>12}"
                )

    print("\nFAILS = that impl could not read back data a previous process wrote.")
    print("'per element' is (facade - correct) spread over keys x listLen: the wrapper's own cost.")

    print("\n=== RSS across the timed window (MB), List<String> ===")
    print(
        "Reads should be flat across impls (the cast view is documented zero-copy); writes should"
    )
    print("show the defensive copy, which `correct` pays too.\n")
    header = f"{'mode':<8} {'len':>5} {'naive':>9} {'correct':>9} {'facade':>9}"
    print(header)
    print("-" * len(header))
    for mode in MODES:
        for list_len in list_lens:
            medians = [rss(rows, mode=mode, impl=impl, list_len=list_len) for impl in IMPLS]
            if any(value is None for value in medians):
                continue
            print(
                f"{mode:<8} {list_len:>5} " + " ".join(f"{value / 1e6:>9.2f}" for value in medians)
            )


def rss(rows, *, mode, impl, list_len, elem="str"):
    """Median RSS delta for one cell. Only the `str` axis, since memory is element-type-agnostic."""
    values = [
        row["rssDeltaBytes"]
        for row in rows
        if row.get("mode") == mode
        and row.get("impl") == impl
        and row.get("elem") == elem
        and row.get("listLen") == list_len
        and row.get("rssDeltaBytes")
    ]

    return statistics.median(values) if values else None


if __name__ == "__main__":
    main()
