#!/bin/bash
# Key-codec matrix driver. Usage: driver.sh <bench-executable> <out.jsonl> [reps] ["scales"]
# JIT lane: benchmark/bench_jit.sh as <bench-executable>. AOT (deciding) lane:
# `dart compile exe benchmark/bench.dart` first and pass the produced executable.
#
# Every read/write lane runs twice, once per impl (raw hive_ce, then the shipped façade), so the
# JSONL carries both the façade numbers the README quotes and the raw baseline they are measured
# against. Prep runs once per (keyKind, scale) and both impls read that one file: the shipped
# codecs encode byte-identically to key_codecs.dart, so this stays like-for-like.
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
    "$BIN" prep raw "$kind" "$n" eager "$work" >> "$OUT"
    for _ in $(seq "$REPS"); do
      for impl in raw facade; do
        "$BIN" open "$impl" "$kind" "$n" eager "$work" >> "$OUT"
        "$BIN" open "$impl" "$kind" "$n" lazy "$work" >> "$OUT"
        "$BIN" get "$impl" "$kind" "$n" eager "$work" >> "$OUT"
        "$BIN" get "$impl" "$kind" "$n" lazy "$work" >> "$OUT"
        if [ "$n" -ge 100000 ]; then
          "$BIN" scanread "$impl" "$kind" "$n" eager "$work" >> "$OUT"
          "$BIN" scanread "$impl" "$kind" "$n" lazy "$work" >> "$OUT"
        fi
      done
      # Historical count-only scan: raw-only, kept so the pre-1.0 results stay comparable.
      if [ "$n" -ge 100000 ]; then
        "$BIN" scan raw "$kind" "$n" lazy "$work" >> "$OUT"
      fi
    done
    rm -rf "$work"
    for _ in $(seq "$REPS"); do
      for impl in raw facade; do
        if [ "$n" -le 10000 ]; then
          "$BIN" put "$impl" "$kind" "$n" >> "$OUT"
        fi
        "$BIN" putall "$impl" "$kind" "$n" >> "$OUT"
      done
    done
  done
done

# bit-shift reference lane, one macro scale. Raw-only: no shipped codec packs that way
# (PackedIntDualCodec is byte-identical for in-range parts, which is what keeps 0.0.x boxes
# readable, so a façade lane here would just re-measure arith).
work="$(mktemp -d "${TMPDIR:-/tmp}/hbm_work.XXXXXX")"
"$BIN" prep raw bitshift 10000 eager "$work" >> "$OUT"
for _ in $(seq "$REPS"); do
  "$BIN" open raw bitshift 10000 eager "$work" >> "$OUT"
  "$BIN" get raw bitshift 10000 eager "$work" >> "$OUT"
  "$BIN" get raw bitshift 10000 lazy "$work" >> "$OUT"
done
rm -rf "$work"

# micro lane (diagnostic): codec pack/unpack in isolation, both impls where one exists.
for kind in arith string; do
  for impl in raw facade; do
    for _ in $(seq "$REPS"); do
      "$BIN" micro "$impl" "$kind" 0 >> "$OUT"
    done
  done
done
for _ in $(seq "$REPS"); do
  "$BIN" micro raw bitshift 0 >> "$OUT"
done

echo "driver done: $(wc -l < "$OUT") records" >&2
