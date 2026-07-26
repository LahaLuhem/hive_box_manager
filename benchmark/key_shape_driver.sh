#!/bin/bash
# Key-shape driver: prices the type shapes behind the dual family's overhead.
# Usage: key_shape_driver.sh <bench-executable> <out.jsonl> [reps] [n]
# AOT only: `dart compile exe benchmark/key_shape_bench.dart` first. JIT answers a different
# question, since the effect is an AOT subtype-check path.
#
# No disk and no prepped box, unlike the other drivers: the store is an in-process Map (the bench
# header says why). Load stamp still recorded, though these lanes barely move with it.
#
# Lane order is the argument, read top to bottom; raw-generic-adapter vs raw-concrete-adapter is
# the pair that carries it.
# shellcheck disable=SC2129  # per-invocation appends are deliberate: one measurement per subprocess, one line each
set -euo pipefail

BIN="$1"
OUT="$2"
REPS="${3:-7}"
N="${4:-2000000}"

# Both-format tolerant: macOS says "load averages: a b c", GNU says "load average: a, b, c".
current_load() { uptime | sed -E 's/.*load averages?: *//; s/,/ /g; s/  */ /g; s/ *$//'; }

LOAD_START="$(current_load)"

: > "$OUT"

LANES="generic-int generic-string generic-record raw-generic-adapter raw-concrete-adapter raw-widened-adapter raw-object-record raw-direct"

for _ in $(seq "$REPS"); do
  for lane in $LANES; do
    "$BIN" "$lane" "$N" >> "$OUT"
  done
done

printf '{"mode":"meta","reps":%s,"n":%s,"loadStart":"%s","loadEnd":"%s"}\n' \
  "$REPS" "$N" "$LOAD_START" "$(current_load)" >> "$OUT"

echo "key-shape driver done: $(wc -l < "$OUT") records; load $LOAD_START -> $(current_load)" >&2
