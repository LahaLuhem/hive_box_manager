#!/bin/bash
# List-box-lane driver. Usage: list_box_driver.sh <bench-executable> <out.jsonl> [reps] [keys] ["listLens"]
# AOT (the deciding lane): `dart compile exe benchmark/list_box_bench.dart` first and pass the
# produced executable.
#
# Three impls (naive / correct / facade) x two element types (str / obj) x the elements-per-key axis.
# Box size (keys) is held constant on purpose: elements per key is what every cost on this surface
# scales with, and varying both axes at once would make the curves unreadable.
#
# The read lanes share one prepped box per (elem, listLen), so all three impls read byte-identical
# data. The write lanes each own their box, because they mutate it.
# shellcheck disable=SC2129  # per-invocation appends are deliberate: one measurement per subprocess, one line each
set -euo pipefail

BIN="$1"
OUT="$2"
REPS="${3:-5}"
KEYS="${4:-200}"
LIST_LENS="${5:-1 10 100 1000}"

current_load() { uptime | sed -E 's/.*load averages?: *//; s/,/ /g; s/  */ /g; s/ *$//'; }

LOAD_START="$(current_load)"

: > "$OUT"

for elem in str obj; do
  for len in $LIST_LENS; do
    work="$(mktemp -d "${TMPDIR:-/tmp}/hbm_list_box.XXXXXX")"
    "$BIN" prep shared "$elem" "$KEYS" "$len" "$work" >> "$OUT"
    for _ in $(seq "$REPS"); do
      for impl in naive correct facade; do
        "$BIN" open "$impl" "$elem" "$KEYS" "$len" "$work" >> "$OUT"
        "$BIN" get "$impl" "$elem" "$KEYS" "$len" "$work" >> "$OUT"
      done
    done
    rm -rf "$work"
    for _ in $(seq "$REPS"); do
      for impl in naive correct facade; do
        "$BIN" put "$impl" "$elem" "$KEYS" "$len" >> "$OUT"
        "$BIN" putall "$impl" "$elem" "$KEYS" "$len" >> "$OUT"
        "$BIN" add "$impl" "$elem" "$KEYS" "$len" >> "$OUT"
        "$BIN" remove "$impl" "$elem" "$KEYS" "$len" >> "$OUT"
      done
    done
  done
done

printf '{"mode":"meta","reps":%s,"keys":%s,"listLens":"%s","loadStart":"%s","loadEnd":"%s"}\n' \
  "$REPS" "$KEYS" "$LIST_LENS" "$LOAD_START" "$(current_load)" >> "$OUT"

echo "list-box driver done: $(wc -l < "$OUT") records; load $LOAD_START -> $(current_load)" >&2
