#!/bin/bash
# Wrapper-overhead driver (aim #4's proof; target: within noise, under 5%).
# Usage: overhead_driver.sh <bench-executable> <out.jsonl> [reps] [get_n] [put_n]
# AOT (the deciding lane): `dart compile exe benchmark/overhead_bench.dart` first and pass the
# produced executable.
# shellcheck disable=SC2129  # per-invocation appends are deliberate: one measurement per subprocess, one line each
set -euo pipefail

BIN="$1"
OUT="$2"
REPS="${3:-5}"
GET_N="${4:-100000}"
PUT_N="${5:-10000}"

: > "$OUT"

work="$(mktemp -d "${TMPDIR:-/tmp}/hbm_overhead.XXXXXX")"
"$BIN" prep "$GET_N" "$work" >> "$OUT"
for _ in $(seq "$REPS"); do
  for impl in raw facade; do
    "$BIN" get "$impl" "$GET_N" eager "$work" >> "$OUT"
    "$BIN" get "$impl" "$GET_N" lazy "$work" >> "$OUT"
  done
done
rm -rf "$work"

for _ in $(seq "$REPS"); do
  for impl in raw facade; do
    "$BIN" put "$impl" "$PUT_N" >> "$OUT"
  done
done
