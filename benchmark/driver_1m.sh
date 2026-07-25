#!/bin/bash
# 1M open-only pass. Usage: driver_1m.sh <bench-executable> <out.jsonl> [reps]
# Separate from driver.sh because only the open lane is worth running at this scale: a full
# eager-get pass over 1M entries measures nothing the 100K point does not already show, and
# putAll at 1M would dominate the run for a row no table quotes. Open is the row that matters,
# because open cost and keystore RSS both track file size (that is the eager-vs-lazy chart).
# shellcheck disable=SC2129  # per-invocation appends are deliberate: one measurement per subprocess, one line each
set -euo pipefail

BIN="$1"
OUT="$2"
REPS="${3:-3}"
N=1000000

: > "$OUT"

for kind in arith string; do
  work="$(mktemp -d "${TMPDIR:-/tmp}/hbm_1m.XXXXXX")"
  "$BIN" prep raw "$kind" "$N" eager "$work" >> "$OUT"
  for _ in $(seq "$REPS"); do
    for impl in raw facade; do
      "$BIN" open "$impl" "$kind" "$N" eager "$work" >> "$OUT"
      "$BIN" open "$impl" "$kind" "$N" lazy "$work" >> "$OUT"
    done
  done
  rm -rf "$work"
done

echo "1m driver done: $(wc -l < "$OUT") records" >&2
