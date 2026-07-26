#!/bin/bash
# Wrapper-overhead driver (aim #4's proof; target: within noise, under 5%).
# Usage: overhead_driver.sh <bench-executable> <out.jsonl> [reps] [get_n] [put_n] [by_n]
# AOT (the deciding lane): `dart compile exe benchmark/overhead_bench.dart` first and pass the
# produced executable.
#
# GET_N sizes the read lanes (a full pass costs one op per entry); PUT_N sizes every lane that pays
# a disk round-trip per op, which is the write lanes plus the lazy read lanes.
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
# The putAllBy lane gets its own, larger size: it is one batched call, so a big n is cheap, and the
# few-percent effect it measures does not clear this host's rep noise at PUT_N. The per-op write
# lanes cannot follow, because each of their ops is a disk round-trip.
BY_N="${6:-100000}"

# Both-format tolerant: macOS says "load averages: a b c", GNU says "load average: a, b, c".
current_load() { uptime | sed -E 's/.*load averages?: *//; s/,/ /g; s/  */ /g; s/ *$//'; }

LOAD_START="$(current_load)"

: > "$OUT"

# Two prepped boxes. The big one serves every lane that samples keys out of it; the small one exists
# for lazy `values`, which reads the *whole* box in one parallel fetch and would mean 100K concurrent
# disk reads against the big one.
big="$(mktemp -d "${TMPDIR:-/tmp}/hbm_overhead_big.XXXXXX")"
small="$(mktemp -d "${TMPDIR:-/tmp}/hbm_overhead_small.XXXXXX")"
"$BIN" prep "$GET_N" "$big" >> "$OUT"
"$BIN" prep "$PUT_N" "$small" >> "$OUT"

for _ in $(seq "$REPS"); do
  for impl in raw facade; do
    # Read lanes off the shared boxes.
    "$BIN" get "$impl" "$GET_N" eager "$big" >> "$OUT"
    "$BIN" get "$impl" "$GET_N" lazy "$big" >> "$OUT"
    "$BIN" values "$impl" "$GET_N" eager "$big" >> "$OUT"
    "$BIN" values "$impl" "$PUT_N" lazy "$small" >> "$OUT"
    "$BIN" contains "$impl" "$GET_N" eager "$big" >> "$OUT"
    "$BIN" contains "$impl" "$GET_N" lazy "$big" >> "$OUT"
  done
done
rm -rf "$big" "$small"

for _ in $(seq "$REPS"); do
  for impl in raw facade; do
    # Write lanes own their box: each one mutates, so none can share a prepped file.
    "$BIN" put "$impl" "$PUT_N" >> "$OUT"
    "$BIN" putall "$impl" "$PUT_N" >> "$OUT"

    "$BIN" delete "$impl" "$PUT_N" >> "$OUT"
    "$BIN" deleteall "$impl" "$PUT_N" >> "$OUT"
    # Single-value façades: one fixed slot, so n is the op count, not a box size.
    "$BIN" single "$impl" get "$GET_N" eager >> "$OUT"
    "$BIN" single "$impl" get "$PUT_N" lazy >> "$OUT"
    "$BIN" single "$impl" set "$PUT_N" eager >> "$OUT"
    "$BIN" single "$impl" set "$PUT_N" lazy >> "$OUT"
  done
done

# putAllBy lane: its impl axis is map|facade (the two ways to write the same call), not raw|facade,
# because there is no raw hive_ce counterpart to compare against. See the bench's own header.
for _ in $(seq "$REPS"); do
  for impl in map facade; do
    "$BIN" putallby "$impl" "$BY_N" >> "$OUT"
  done
done

printf '{"mode":"meta","reps":%s,"getN":%s,"putN":%s,"byN":%s,"loadStart":"%s","loadEnd":"%s"}\n' \
  "$REPS" "$GET_N" "$PUT_N" "$BY_N" "$LOAD_START" "$(current_load)" >> "$OUT"

echo "overhead driver done: $(wc -l < "$OUT") records; load $LOAD_START -> $(current_load)" >&2
