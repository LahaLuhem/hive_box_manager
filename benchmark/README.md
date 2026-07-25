# Benchmarks

Maintainer tooling, excluded from the published tarball. Two lanes live here:

- **Key-codec matrix** (`bench.dart` + `driver.sh`, plus `driver_1m.sh` for the open-only 1M
  pass): measures put / putAll / open / get / scan / query / RSS / file size per key-encoding
  scheme (arithmetic packed int, String composite, 0.0.x bit-shift reference) at 1K/10K/100K.
- **Wrapper-overhead lane** (`overhead_bench.dart` + `overhead_driver.sh`): façade vs raw
  hive_ce on eager get (100K random gets), lazy get (10K ops over 100K entries), and single
  puts (10K); the aim-#4 proof with its under-5% target. The eager read path carries
  `vm:prefer-inline` pragmas exactly because this lane holds it to raw speed.

## The `impl` axis

Every matrix lane runs twice, once per `impl`:

- `facade` drives the shipped `DualKeyBox` / `LazyDualKeyBox` through the shipped
  `PackedIntDualCodec` / `StringCompositeDualCodec`. **These are the numbers the top-level
  README's performance table quotes.**
- `raw` drives `hive_ce` directly with the hand-inlined pack/unpack in `key_codecs.dart`. It is
  the historical baseline (this lane started life as the pre-1.0 planning study, which only ever
  measured raw) and the denominator for the matrix lane's overhead percentages.

The driver preps one box file per (keyKind, scale) and points both impls at it. That works only
because the shipped codecs encode byte-identically to `key_codecs.dart`; keep them that way or
the two impls quietly stop comparing like with like.

`bitshift` is raw-only. No shipped codec packs that way, because `PackedIntDualCodec` is
byte-identical to it for in-range parts (which is what lets 0.0.x boxes read in place), so a
façade lane there would just re-measure `arith`.

Two scan modes, deliberately:

- `scan` reads nothing, only decodes every live key and counts primary matches. Raw-only, kept
  verbatim so the pre-1.0 result rows stay comparable.
- `scanread` scans *and* reads every match, which is what `queryByPrimary` actually does. This is
  the mode with a façade counterpart, so it is the one to compare.

## Running the overhead lane

```sh
dart compile exe benchmark/overhead_bench.dart -o /tmp/hbm_overhead
benchmark/overhead_driver.sh /tmp/hbm_overhead /tmp/overhead.jsonl
```

## Running the matrix

```sh
# Quick JIT sanity pass (ordering only; not for decisions):
benchmark/driver.sh benchmark/bench_jit.sh /tmp/results_jit.jsonl 3

# AOT pass (the numbers that decide anything):
dart compile exe benchmark/bench.dart -o /tmp/hbm_bench
benchmark/driver.sh /tmp/hbm_bench /tmp/results_aot.jsonl

# 1M open-only pass, same executable:
benchmark/driver_1m.sh /tmp/hbm_bench /tmp/results_1m.jsonl
```

Each invocation is one fresh process per measurement; the driver writes one JSON line per run.

## `results/`

Raw JSONL backing the top-level README's performance tables and codec-crossover guidance:
`results_aot.jsonl` (deciding lane), `results_jit.jsonl` (sanity), `results_1m.jsonl` (1M
open-only).

Environment: macOS 15.7.7 on Apple Silicon (arm64), Dart 3.12.2, hive_ce 2.19.3, 2026-07-25.
Values were a constant 1 byte by design, isolating key cost; web performance is unmeasured
(ordering assumed to follow the VM).

Re-stamp this section whenever the results are regenerated. A number with no environment behind
it is not a measurement.

## `reports/`

Charts rendered from `results/` by [`python/plot.py`](python/plot.py) and committed as PNGs. The
top-level README references them by absolute raw GitHub URL, so they render on pub.dev without
shipping in the tarball (`benchmark/` is `.pubignore`d). Four charts: codec get + keystore-RSS
scaling (packed vs String), and open time + per-read latency (eager vs lazy). Built with seaborn
over matplotlib, data in polars (seaborn reads polars frames directly via the dataframe
interchange protocol), matching the sibling packages' chart style. Colours are the Okabe-Ito
CVD-safe pair, with line style and marker as a second cue so identity never rests on colour alone.

The Python lives in [`python/`](python/) as a [`uv`](https://docs.astral.sh/uv/) project
(`pyproject.toml` + committed `uv.lock` + `.python-version`), so nothing installs onto your machine
globally. Regenerate whenever the results change:

```sh
uv sync --project benchmark/python                # create .venv, install the pinned stack
uv run --project benchmark/python python plot.py  # rewrite reports/*.png
```
