# Benchmarks

Maintainer tooling, excluded from the published tarball. Two lanes live here:

- **Key-codec matrix** (`bench.dart` + `driver.sh`): the P1/P7 harness from the 1.0 planning
  session, kept for regression runs. It measures put / putAll / open / get / scan / RSS / file
  size per key-encoding scheme (arithmetic packed int, String composite, 0.0.x bit-shift
  reference) at 1K/10K/100K, plus a 1M open-only pass.
- **Wrapper-overhead lane** (`overhead_bench.dart` + `overhead_driver.sh`): façade vs raw
  hive_ce on eager get (100K random gets), lazy get (10K ops over 100K entries), and single
  puts (10K); the aim-#4 proof with its under-5% target. The eager read path carries
  `vm:prefer-inline` pragmas exactly because this lane holds it to raw speed.

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
```

Each invocation is one fresh process per measurement; the driver writes one JSON line per run.

## `results/`

Raw JSONL from the planning-session runs backing the rewrite plan's benchmark tables and the
README's codec-crossover guidance: `results_aot.jsonl` (deciding lane), `results_jit.jsonl`
(sanity), `results_1m.jsonl` (1M open-only). Environment: macOS Apple Silicon, Dart 3.12.2,
hive_ce 2.19.3, 2026-07-20. Values were a constant 1 byte by design, isolating key cost; web
performance is unmeasured (ordering assumed to follow the VM).
