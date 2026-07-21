# Benchmarks

Maintainer tooling, excluded from the published tarball. Two lanes live (or will live) here:

- **Key-codec matrix** (`bench.dart` + `driver.sh`): the P1/P7 harness from the 1.0 planning
  session, kept for regression runs. It measures put / putAll / open / get / scan / RSS / file
  size per key-encoding scheme (arithmetic packed int, String composite, 0.0.x bit-shift
  reference) at 1K/10K/100K, plus a 1M open-only pass.
- **Wrapper-overhead lane**: arrives with build Phase 4 (façade vs raw hive_ce; target within
  noise, under 5%).

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
