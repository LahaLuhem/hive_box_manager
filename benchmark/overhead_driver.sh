#!/bin/bash
# Wrapper-overhead driver (aim #4's proof; target: within noise, under 5%).
# Usage: overhead_driver.sh <bench-executable> <out.jsonl> [reps] [get_n] [put_n]
# AOT (the deciding lane): `dart compile exe benchmark/overhead_bench.dart` first and pass the
# produced executable.
#
# This lane resolves single-digit percentages, so background load on the host swamps the signal
# outright: an otherwise identical pass taken under load average 10 moved a +2% lane to +27% and
# spread individual samples 54..192 ms. Run it on a quiet machine, and read the load stamp this
# writes into the JSONL before trusting any percentage derived from it (python/overhead.py prints
# the stamp and cross-checks median against min for exactly that reason).
# shellcheck disable=SC2129  # per-invocation appends are deliberate: one measurement per subprocess, one line each
set -euo pipefail

BIN="$1"
OUT="$2"
REPS="${3:-9}"
GET_N="${4:-100000}"
PUT_N="${5:-10000}"

# Both-format tolerant: macOS says "load averages: a b c", GNU says "load average: a, b, c".
current_load() { uptime | sed -E 's/.*load averages?: *//; s/,/ /g; s/  */ /g; s/ *$//'; }

LOAD_START="$(current_load)"

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

printf '{"mode":"meta","reps":%s,"getN":%s,"putN":%s,"loadStart":"%s","loadEnd":"%s"}\n' \
  "$REPS" "$GET_N" "$PUT_N" "$LOAD_START" "$(current_load)" >> "$OUT"

echo "overhead driver done: $(wc -l < "$OUT") records; load $LOAD_START -> $(current_load)" >&2
