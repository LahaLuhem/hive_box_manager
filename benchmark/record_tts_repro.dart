// Standalone repro for dart-lang/sdk#61970, cut down from the key-shape lane.
//
// An `AssertAssignable` whose destination type is a record built from the enclosing class's own
// type parameters gets no specialised type testing stub and is never cached, so every check enters
// the C++ runtime. Same IL instruction against a plain type parameter is ~100x cheaper.
//
// No package dependencies, so it runs anywhere:
//
//   dart compile exe benchmark/record_tts_repro.dart -o /tmp/repro && /tmp/repro
//
// Each lane does exactly one interface call per iteration. They differ only in the *kind* of the
// callee's parameter type, which is the whole argument.
//
// AOT only. JIT answers a different question, as the key-shape lane's header explains.
import 'dart:io';

// Named constructors, not 3.13's `const new()`: this file has to compile on 3.12.2 as well,
// since comparing the two SDKs is the point of it.
// ignore_for_file: unnecessary_type_name_in_constructor

// This file is a worker entrypoint, and the lanes are the point rather than any one class
// ignore: prefer-match-file-name
/// One-argument codec interface. Three copies exist so each lane's call site stays monomorphic.
abstract interface class Codec1<K extends Object> {
  /// Encodes [key].
  Object encode(K key);
}

/// As [Codec1], for the three-field lane.
abstract interface class Codec2<K extends Object> {
  /// Encodes [key].
  Object encode(K key);
}

/// As [Codec1], for the four-field lane.
abstract interface class Codec3<K extends Object> {
  /// Encodes [key].
  Object encode(K key);
}

/// Control: the parameter type is concrete, so the check is elided at compile time.
final class ConcretePair implements Codec1<(int, int)> {
  /// Const, matching the shape the real codecs present at the call site.
  const ConcretePair();

  @override
  Object encode((int, int) key) => key.$1;
}

/// Control: the parameter type is the class's own type parameter and not a record. Emits
/// `AssertAssignable` against a `TypeParameter`, which the subtype test cache handles.
final class GenericScalar<A extends Object> implements Codec1<A> {
  /// Const, as above.
  const GenericScalar();

  @override
  Object encode(A key) => key;
}

/// Subject: the parameter type is a record built from the class's type parameters. Emits
/// `AssertAssignable` against an uninstantiated `_RecordType`.
final class GenericPair<A extends Object, B extends Object> implements Codec1<(A, B)> {
  /// Const, as above.
  const GenericPair();

  @override
  Object encode((A, B) key) => key.$1;
}

/// As [GenericPair] with three fields, to show the cost scales per field.
final class GenericTriple<A extends Object, B extends Object, C extends Object>
    implements Codec2<(A, B, C)> {
  /// Const, as above.
  const GenericTriple();

  @override
  Object encode((A, B, C) key) => key.$1;
}

/// As [GenericPair] with four fields.
final class GenericQuad<A extends Object, B extends Object, C extends Object, D extends Object>
    implements Codec3<(A, B, C, D)> {
  /// Const, as above.
  const GenericQuad();

  @override
  Object encode((A, B, C, D) key) => key.$1;
}

/// Sample size: small and power-of-two, so it stays cache-resident and the index wrap is a mask.
const sampleSize = 4096;

/// Index mask derived from [sampleSize].
const mask = sampleSize - 1;

/// Ops for the lanes that pay nothing, sized to clear the noise floor at ~3 ns each.
const freeOps = 20000000;

/// Ops for the lanes that pay the runtime check, sized to keep each pass under a second.
const paidOps = 1000000;

void main() {
  final ints = <int>[for (var i = 0; i < sampleSize; i++) i];
  final pairs = <(int, int)>[for (var i = 0; i < sampleSize; i++) (i, i + 1)];
  final triples = <(int, int, int)>[for (var i = 0; i < sampleSize; i++) (i, i + 1, i + 2)];
  final quads = <(int, int, int, int)>[
    for (var i = 0; i < sampleSize; i++) (i, i + 1, i + 2, i + 3),
  ];

  const Codec1<(int, int)> concrete = ConcretePair();
  const Codec1<int> scalar = GenericScalar();
  const Codec1<(int, int)> pair = GenericPair();
  const Codec2<(int, int, int)> triple = GenericTriple();
  const Codec3<(int, int, int, int)> quad = GenericQuad();

  stdout
    ..writeln(Platform.version)
    ..writeln();

  // Summed so no lane can be optimised away silently.
  var checksum = 0;
  checksum += time('concrete-pair', freeOps, (i) => concrete.encode(pairs[i & mask]) as int);
  checksum += time('generic-scalar', freeOps, (i) => scalar.encode(ints[i & mask]) as int);
  checksum += time('generic-pair', paidOps, (i) => pair.encode(pairs[i & mask]) as int);
  checksum += time('generic-triple', paidOps, (i) => triple.encode(triples[i & mask]) as int);
  checksum += time('generic-quad', paidOps, (i) => quad.encode(quads[i & mask]) as int);
  if (checksum == 0) stdout.writeln('checksum collapsed, a lane is dead');
}

/// Runs [op] for [n] iterations twice, timing the second pass, and prints one line.
int time(String lane, int n, int Function(int index) op) {
  var checksum = 0;
  // Warm-up: AOT has no JIT to warm, but the first pass faults in the sample's pages.
  for (var i = 0; i < n; i++) {
    checksum += op(i);
  }

  final watch = Stopwatch()..start();
  for (var i = 0; i < n; i++) {
    checksum += op(i);
  }
  watch.stop();

  final ns = watch.elapsedMicroseconds * 1000 / n;
  stdout.writeln('${lane.padRight(16)}${ns.toStringAsFixed(2).padLeft(9)} ns/op');

  return checksum;
}
