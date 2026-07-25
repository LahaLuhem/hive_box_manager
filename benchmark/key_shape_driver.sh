#!/bin/bash
# Key-shape driver: prices the type shapes behind the dual family's overhead.
# Usage: key_shape_driver.sh <bench-executable> <out.jsonl> [reps] [n]
# AOT (the deciding lane): `dart compile exe benchmark/key_shape_bench.dart` first and pass the
# produced executable. A JIT run answers a different question, because the whole effect is an AOT
# subtype-check path.
#
# Unlike the other drivers this one touches no disk and prepares no box: the lanes measure a type
# shape, so the store is an in-process Map (see the bench's header for why). That also means the
# lanes are far less load-sensitive than the overhead lane, though the load stamp is still recorded
# so a reading taken on a busy host can be spotted after the fact.
#
# The lane order is deliberate: each one moves a single variable relative to its neighbour, and
# reading them top to bottom is the argument. raw-generic-adapter vs raw-concrete-adapter is the
# pair that carries it.
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
