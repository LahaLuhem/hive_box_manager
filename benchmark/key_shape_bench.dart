// Key-shape lane: which Dart type shape costs the dual family its overhead.
// One measurement per process invocation; emits one JSON line. Drive via key_shape_driver.sh.
//
// Exists because issue #14's first answer was wrong: one lane dropped the record type argument and
// `DualKeyCodecAdapter` in the same step, so it could not tell which paid. Each lane below moves
// exactly one thing against its neighbour.
//
// The store is a plain Map, not hive: a hive get is ~13 ns and identical in every lane, so it would
// add a constant and a disk dependency while answering nothing. bench.dart owns façade-vs-hive.
//
//   generic-int             Engine generic over the semantic key. Baseline, and what KeyedBox ships.
//   generic-string          Same, over String. Control: a non-record generic is free.
//   generic-record          Engine generic over (int, int) + generic adapter. Pre-fix DualKeyBox.
//   raw-generic-adapter     Engine not generic in the key, same adapter. Isolates the type param.
//   raw-concrete-adapter    Same, adapter with no class type params. Isolates the record param.
//   raw-widened-adapter     Param widened to Object + explicit cast. The check moves, not vanishes.
//   raw-object-record       Generic class, concrete (Object, Object) param. Free, and a trap.
//   raw-direct              Two scalar arguments. The shipped shape.
//
// raw-generic-adapter vs raw-concrete-adapter carries the argument: they differ only in whether the
// record parameter type is built from the enclosing class's own type parameters.
//
// Not a devirtualisation artifact, which is why one-lane-per-process is safe here: a build
// containing only the generic-record shape, const codec, single call site, still pays ~360 ns.
//
// Usage: key_shape_bench <lane> [n]
import 'dart:convert';
import 'dart:io';

/// Default op count per timed pass, sized so the *fast* lanes clear the noise floor: at ~15 ns/op
/// they land near 30 ms here, versus ~1.5 ms (pure scheduling noise) at the 100K other lanes use.
const defaultOps = 2000000;

/// Sample size: small and power-of-two, so it stays cache-resident and the index wrap is a mask.
const keySampleSize = 4096;

/// Fixed seed: every lane walks an identical key sequence.
const sampleSeed = 7;

/// Stands in for a consumer's adapter-registered class.
// This file is a worker entrypoint (`key_shape_bench`, per key_shape_driver.sh)
// ignore: prefer-match-file-name
final class Payload {
  /// Summed into the checksum, so no lane can be optimised away silently.
  final int id;

  /// Wraps [id].
  const new(this.id);
}

/// Stand-in for fpdart's `Some`: one allocation per hit, identical in every lane.
final class Hit {
  /// The value found, `null` when the key was absent.
  final Payload? value;

  /// Wraps [value].
  const new(this.value);
}

/// Mirrors the package's real `KeyCodec`: encodes a semantic key into hive's raw domain.
abstract interface class KeyCodec<K extends Object> {
  /// Encodes [key] into the raw domain.
  Object encode(K key);

  /// Decodes [rawKey] back into [K].
  K decode(Object rawKey);
}

/// Mirrors the package's real `DualKeyCodec`: two parts in, one raw key out.
abstract interface class DualKeyCodec<K1 extends Object, K2 extends Object> {
  /// Encodes ([primary], [secondary]) into the raw domain.
  Object encode(K1 primary, K2 secondary);

  /// Decodes [rawKey] back into its two parts.
  (K1, K2) decode(Object rawKey);
}

/// Identity codec for `int` keys.
final class IntKeyCodec implements KeyCodec<int> {
  /// Const, matching the shape the shipped codecs present at the call site.
  const new();

  @override
  Object encode(int key) => key;

  @override
  int decode(Object rawKey) => rawKey as int;
}

/// Identity codec for `String` keys.
final class StringKeyCodec implements KeyCodec<String> {
  /// Const, as above.
  const new();

  @override
  Object encode(String key) => key;

  @override
  String decode(Object rawKey) => rawKey as String;
}

/// Replicates the shipped `PackedIntDualCodec`: two 16-bit parts packed into one int.
final class PackedIntDualCodec implements DualKeyCodec<int, int> {
  /// Const, as above.
  const new();

  @override
  Object encode(int primary, int secondary) => (primary << 16) | secondary;

  @override
  (int, int) decode(Object rawKey) {
    final packed = rawKey as int;

    return (packed >> 16, packed & 0xFFFF);
  }
}

/// Replicates the since-deleted `DualKeyCodecAdapter`: its record parameter is built from this
/// class's own type parameters, which is the defect being priced.
final class GenericDualAdapter<K1 extends Object, K2 extends Object> implements KeyCodec<(K1, K2)> {
  final DualKeyCodec<K1, K2> _dualCodec;

  /// Wraps [_dualCodec].
  const new(this._dualCodec);

  @override
  Object encode((K1, K2) key) => _dualCodec.encode(key.$1, key.$2);

  @override
  (K1, K2) decode(Object rawKey) => _dualCodec.decode(rawKey);
}

/// The same adapter with no class type parameters, so its record parameter is concrete. The one
/// variable separating it from [GenericDualAdapter].
final class ConcreteDualAdapter implements KeyCodec<(int, int)> {
  final DualKeyCodec<int, int> _dualCodec;

  /// Wraps [_dualCodec].
  const new(this._dualCodec);

  @override
  Object encode((int, int) key) => _dualCodec.encode(key.$1, key.$2);

  @override
  (int, int) decode(Object rawKey) => _dualCodec.decode(rawKey);
}

/// Parameter widened to `Object`, moving the record check into an explicit cast. Legal Dart, and
/// no help: it is the same check.
final class WidenedDualAdapter<K1 extends Object, K2 extends Object> implements KeyCodec<(K1, K2)> {
  final DualKeyCodec<K1, K2> _dualCodec;

  /// Wraps [_dualCodec].
  const new(this._dualCodec);

  @override
  Object encode(Object key) {
    final (primary, secondary) = key as (K1, K2);

    return _dualCodec.encode(primary, secondary);
  }

  @override
  (K1, K2) decode(Object rawKey) => _dualCodec.decode(rawKey);
}

/// Generic class, concrete record parameter. Fast, and a trap: it hides the cost while keeping a
/// record on the boundary, so the defect returns the moment someone re-parameterises it.
final class ObjectRecordDualAdapter<K1 extends Object, K2 extends Object>
    implements KeyCodec<(Object, Object)> {
  final DualKeyCodec<K1, K2> _dualCodec;

  /// Wraps [_dualCodec].
  const new(this._dualCodec);

  @override
  Object encode((Object, Object) key) => _dualCodec.encode(key.$1 as K1, key.$2 as K2);

  @override
  (Object, Object) decode(Object rawKey) => _dualCodec.decode(rawKey);
}

/// Generic over the semantic key, owning its codec: the pre-fix shape.
final class SemanticKeyEngine<T extends Object, K extends Object> {
  final Map<Object, Object?> _store;
  final KeyCodec<K> _keyCodec;

  /// Wires the engine over [_store] with [_keyCodec].
  new(this._store, this._keyCodec);

  /// Reads [key], encoding through the codec first.
  // Inlined to match the shipped engine's pragma.
  @pragma('vm:prefer-inline')
  Hit get(K key) {
    final stored = _store[_keyCodec.encode(key)];

    return stored == null ? const Hit(null) : Hit(stored as Payload);
  }
}

/// Takes an already-encoded key, with no key type parameter: the post-fix shape.
final class RawKeyEngine<T extends Object> {
  final Map<Object, Object?> _store;

  /// Wires the engine over [_store].
  new(this._store);

  /// Reads [rawKey] directly.
  @pragma('vm:prefer-inline')
  Hit get(Object rawKey) {
    final stored = _store[rawKey];

    return stored == null ? const Hit(null) : Hit(stored as Payload);
  }
}

void main(List<String> args) {
  switch (args) {
    case [final lane]:
      runLane(lane, defaultOps);
    case [final lane, final n]:
      runLane(lane, int.parse(n));
    default:
      stderr.writeln('usage: key_shape_bench <lane> [n]');
      exitCode = 64;
  }
}

/// Round-trips every replica codec before any lane runs.
///
/// A codec that failed would miss on every op, which reads as a very fast lane rather than a broken
/// one. That is how a benchmark starts lying, so it is a hard gate, not a note in the output.
bool codecsRoundTrip() {
  const packed = PackedIntDualCodec();
  const KeyCodec<int> ints = IntKeyCodec();
  const KeyCodec<String> strings = StringKeyCodec();
  const KeyCodec<(int, int)> generic = GenericDualAdapter(packed);
  const KeyCodec<(int, int)> concrete = ConcreteDualAdapter(packed);
  const KeyCodec<(int, int)> widened = WidenedDualAdapter(packed);
  const KeyCodec<(Object, Object)> objectRecord = ObjectRecordDualAdapter<int, int>(packed);

  return ints.decode(ints.encode(7)) == 7 &&
      strings.decode(strings.encode('k7')) == 'k7' &&
      packed.decode(packed.encode(7, 9)) == (7, 9) &&
      generic.decode(generic.encode((7, 9))) == (7, 9) &&
      concrete.decode(concrete.encode((7, 9))) == (7, 9) &&
      widened.decode(widened.encode((7, 9))) == (7, 9) &&
      objectRecord.decode(objectRecord.encode((7, 9))) == (7, 9);
}

/// Runs [lane] for [n] ops and emits its one JSON line.
void runLane(String lane, int n) {
  if (!codecsRoundTrip()) {
    stderr.writeln('replica codecs do not round-trip: every lane would measure misses');
    exitCode = 70;

    return;
  }

  final pairs = buildPairs();
  final store = <Object, Object?>{};
  const packed = PackedIntDualCodec();
  for (var i = 0; i < pairs.length; i++) {
    final (primary, secondary) = pairs[i];
    store[packed.encode(primary, secondary)] = Payload(i);
  }
  // Single-key lanes share the same store, so every lane sees one map and one allocation profile.
  final ints = [for (var i = 0; i < keySampleSize; i++) i];
  final strings = [for (var i = 0; i < keySampleSize; i++) 'k$i'];
  for (var i = 0; i < keySampleSize; i++) {
    store[ints[i]] = Payload(i);
    store[strings[i]] = Payload(i);
  }

  final op = laneOp(lane, store: store, pairs: pairs, ints: ints, strings: strings);
  if (op == null) {
    stderr.writeln('unknown lane: $lane');
    exitCode = 64;

    return;
  }

  // Warm-up: AOT has no JIT to warm, but the first pass faults in the store's pages, which would
  // otherwise flatter whichever lane ran first.
  var checksum = 0;
  for (var i = 0; i < n; i++) {
    checksum += op(i);
  }

  final watch = Stopwatch()..start();
  for (var i = 0; i < n; i++) {
    checksum += op(i);
  }
  watch.stop();

  emit({
    'mode': 'keyshape',
    'lane': lane,
    'n': n,
    'ms': watch.elapsedMicroseconds / Duration.microsecondsPerMillisecond,
    'nsPerOp': watch.elapsedMicroseconds * 1000 / n,
    // This lane pins compiler behaviour, so the toolchain is part of the result.
    'sdk': Platform.version,
    // Summed, not xor-ed: an xor over a repeating sample cancels to zero and hides a dead lane.
    'checksum': checksum,
  });
}

/// The sample every dual lane walks. Fixed seed, no `Random`: identical across machines and lanes.
List<(int, int)> buildPairs() {
  var seed = sampleSeed;
  int next() => seed = (seed * 1103515245 + 12345) & 0x3FFFFFFF;

  return [for (var i = 0; i < keySampleSize; i++) (next() % 0xFFFF, next() % 0xFFFF)];
}

/// Resolves [lane] to the closure the timed loop calls, or `null` when unknown. Each returns the
/// found payload's id for the checksum; all wiring happens here, outside the timed window.
int Function(int index)? laneOp(
  String lane, {
  required Map<Object, Object?> store,
  required List<(int, int)> pairs,
  required List<int> ints,
  required List<String> strings,
}) {
  const mask = keySampleSize - 1;
  const packed = PackedIntDualCodec();

  switch (lane) {
    case 'generic-int':
      final engine = SemanticKeyEngine<Payload, int>(store, const IntKeyCodec());

      return (index) => engine.get(ints[index & mask]).value?.id ?? 0;

    case 'generic-string':
      final engine = SemanticKeyEngine<Payload, String>(store, const StringKeyCodec());

      return (index) => engine.get(strings[index & mask]).value?.id ?? 0;

    case 'generic-record':
      final engine = SemanticKeyEngine<Payload, (int, int)>(
        store,
        const GenericDualAdapter(packed),
      );

      return (index) => engine.get(pairs[index & mask]).value?.id ?? 0;

    case 'raw-generic-adapter':
      final engine = RawKeyEngine<Payload>(store);
      const KeyCodec<(int, int)> adapter = GenericDualAdapter(packed);

      return (index) => engine.get(adapter.encode(pairs[index & mask])).value?.id ?? 0;

    case 'raw-concrete-adapter':
      final engine = RawKeyEngine<Payload>(store);
      const KeyCodec<(int, int)> adapter = ConcreteDualAdapter(packed);

      return (index) => engine.get(adapter.encode(pairs[index & mask])).value?.id ?? 0;

    case 'raw-widened-adapter':
      final engine = RawKeyEngine<Payload>(store);
      const KeyCodec<(int, int)> adapter = WidenedDualAdapter(packed);

      return (index) => engine.get(adapter.encode(pairs[index & mask])).value?.id ?? 0;

    case 'raw-object-record':
      final engine = RawKeyEngine<Payload>(store);
      const KeyCodec<(Object, Object)> adapter = ObjectRecordDualAdapter<int, int>(packed);

      return (index) => engine.get(adapter.encode(pairs[index & mask])).value?.id ?? 0;

    case 'raw-direct':
      final engine = RawKeyEngine<Payload>(store);
      const DualKeyCodec<int, int> codec = packed;

      return (index) {
        final (primary, secondary) = pairs[index & mask];

        return engine.get(codec.encode(primary, secondary)).value?.id ?? 0;
      };

    default:
      return null;
  }
}

/// Writes one JSON line, matching the other lanes' output contract.
void emit(Map<String, Object?> record) => stdout.writeln(jsonEncode(record));
