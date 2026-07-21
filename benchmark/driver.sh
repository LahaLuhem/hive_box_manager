#!/bin/bash
# P1/P7 matrix driver. Usage: driver.sh <bench-executable> <out.jsonl> [reps] ["scales"]
# JIT lane: benchmark/bench_jit.sh as <bench-executable>. AOT (deciding) lane:
# `dart compile exe benchmark/bench.dart` first and pass the produced executable.
# shellcheck disable=SC2129  # per-invocation appends are deliberate: one measurement per subprocess, one line each
set -euo pipefail

BIN="$1"
OUT="$2"
REPS="${3:-5}"
SCALES="${4:-1000 10000 100000}"

: > "$OUT"

for kind in arith string; do
  for n in $SCALES; do
    work="$(mktemp -d "${TMPDIR:-/tmp}/hbm_work.XXXXXX")"
    "$BIN" prep "$kind" "$n" eager "$work" >> "$OUT"
    for _ in $(seq "$REPS"); do
      "$BIN" open "$kind" "$n" eager "$work" >> "$OUT"
      "$BIN" open "$kind" "$n" lazy "$work" >> "$OUT"
      "$BIN" get "$kind" "$n" eager "$work" >> "$OUT"
      "$BIN" get "$kind" "$n" lazy "$work" >> "$OUT"
      if [ "$n" -ge 100000 ]; then
        "$BIN" scan "$kind" "$n" lazy "$work" >> "$OUT"
      fi
    done
    rm -rf "$work"
    for _ in $(seq "$REPS"); do
      if [ "$n" -le 10000 ]; then
        "$BIN" put "$kind" "$n" >> "$OUT"
      fi
      "$BIN" putall "$kind" "$n" >> "$OUT"
    done
  done
done

# bit-shift reference lane, one macro scale
work="$(mktemp -d "${TMPDIR:-/tmp}/hbm_work.XXXXXX")"
"$BIN" prep bitshift 10000 eager "$work" >> "$OUT"
for _ in $(seq "$REPS"); do
  "$BIN" open bitshift 10000 eager "$work" >> "$OUT"
  "$BIN" get bitshift 10000 eager "$work" >> "$OUT"
  "$BIN" get bitshift 10000 lazy "$work" >> "$OUT"
done
rm -rf "$work"

# micro lane (diagnostic)
for kind in arith string bitshift; do
  for _ in $(seq "$REPS"); do
    "$BIN" micro "$kind" 0 >> "$OUT"
  done
done

echo "driver done: $(wc -l < "$OUT") records" >&2
