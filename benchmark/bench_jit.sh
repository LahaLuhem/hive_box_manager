#!/bin/bash
# JIT wrapper for driver.sh: runs the bench worker via `dart run` from the package root,
# so package resolution comes from the root pubspec.
cd "$(dirname "$0")/.." && exec dart run benchmark/bench.dart "$@"
