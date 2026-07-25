// Key-shape lane: which Dart type shape costs the dual family its overhead.
// One measurement per process invocation; emits one JSON line. Drive via key_shape_driver.sh.
//
// This lane exists because issue #14's first answer was wrong, and wrong in a way that got copied
// into three documents before anyone re-ran it. That experiment compared "engine typed over the
// record" against "engine typed over int", concluded the engine's generic slot was the problem, and
// missed that the same step had also removed `DualKeyCodecAdapter`. Two variables, one lane, wrong
// attribution. The lanes below change exactly one thing at a time so the next person cannot repeat
// that.
//
// What it measures, and what it deliberately does not: this is a *type-shape* question, so the
// store is a plain `Map`, not hive. A hive get costs ~13 ns and is identical across every lane
// here, so including it would add a constant and a disk dependency while answering nothing. The
// façade-versus-raw-hive question is bench.dart's job; this lane isolates the wrapper's own shape.
//
// The eight lanes, and the single variable each one moves:
//
//   generic-int              Engine generic over the semantic key, `int`. The baseline, and the
//                            shape KeyedBox / SingleValueBox actually ship.
//   generic-string           Same, over `String`. Control: proves a non-record generic is free, so
//                            "generics are slow" is not the explanation.
//   generic-record           Engine generic over `(int, int)` + a generic adapter. What DualKeyBox
//                            shipped before the fix.
//   raw-generic-adapter      Engine NOT generic in the key, same generic adapter. Isolates the
//                            engine's type parameter. Equal to generic-record means the type
//                            parameter is innocent.
//   raw-concrete-adapter     Same, but the adapter has no class type parameters. Isolates the
//                            generic record parameter. Free means that parameter is the whole cost.
//   raw-widened-adapter      Generic adapter whose parameter is widened to `Object` (a legal Dart
//                            override) with the record check moved into an explicit cast. Proves
//                            the check cannot be relocated, only avoided.
//   raw-object-record        Generic adapter class with a *concrete* `(Object, Object)` parameter.
//                            Free, and a trap: it fixes the cost while keeping a record on the
//                            engine boundary, so it re-arms the same defect for the next reader.
//   raw-direct               Façade calls `DualKeyCodec.encode(a, b)` with two scalar arguments.
//                            The shipped shape.
//
// The pair that carries the argument is raw-generic-adapter versus raw-concrete-adapter. They
// differ in one thing: whether the record parameter type is built from the enclosing class's own
// type parameters. Everything else about them is identical.
//
// Monomorphism is not the explanation either, and that was worth checking before settling on
// one-lane-per-process: a build containing only the generic-record shape, with a const codec and a
// single call site, still pays the same ~360 ns. The subtype check against a generic-instantiated
// record type is not something devirtualisation removes. So this lane follows the repo's usual
// convention safely, and a reader cannot dismiss the result as a polymorphic-call-site artifact.
//
// Usage: key_shape_bench <lane> [n]
//   lanes: generic-int | generic-string | generic-record | raw-generic-adapter |
//          raw-concrete-adapter | raw-widened-adapter | raw-object-record | raw-direct
import 'dart:convert';
import 'dart:io';

/// Default op count per timed pass.
///
/// Sized so the *fast* lanes clear the noise floor, not the slow one. At roughly 15 ns/op a fast
/// lane needs millions of ops to run long enough to measure; at this count it lands near 30 ms
/// while generic-record lands near 700 ms. Dropping it to the 100K the other lanes use would put
/// every fast lane at ~1.5 ms, which is process-scheduling noise rather than a measurement.
const defaultOps = 2000000;

/// Distinct keys drawn from, kept small and power-of-two so the sample is cache-resident and the
/// index wrap is a mask. Cache misses are noise for a type-shape question.
const keySampleSize = 4096;

/// Fixed seed: every lane walks an identical key sequence.
const sampleSeed = 7;

/// The value type stored, standing in for a consumer's adapter-registered class.
final class Payload {
  /// Payload identity, summed into the checksum so no lane can be optimised away silently.
  final int id;

  /// Wraps [id].
  const Payload(this.id);
}

/// Stand-in for fpdart's `Some`: one allocation per hit, identical in every lane, so the
/// comparison is not distorted by the package's real `Option` contract.
final class Hit {
  /// The value found, `null` when the key was absent.
  final Payload? value;

  /// Wraps [value].
  const Hit(this.value);
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
  /// Const so the call site sees the same shape the package's shipped codecs present.
  const IntKeyCodec();

  @override
  Object encode(int key) => key;

  @override
  int decode(Object rawKey) => rawKey as int;
}

/// Identity codec for `String` keys.
final class StringKeyCodec implements KeyCodec<String> {
  /// Const, as above.
  const StringKeyCodec();

  @override
  Object encode(String key) => key;

  @override
  String decode(Object rawKey) => rawKey as String;
}

/// Replicates the shipped `PackedIntDualCodec`: two 16-bit parts packed into one int.
final class PackedIntDualCodec implements DualKeyCodec<int, int> {
  /// Const, as above.
  const PackedIntDualCodec();

  @override
  Object encode(int primary, int secondary) => (primary << 16) | secondary;

  @override
  (int, int) decode(Object rawKey) {
    final packed = rawKey as int;

    return (packed >> 16, packed & 0xFFFF);
  }
}

/// Replicates the deleted `DualKeyCodecAdapter`: the record parameter is built from this class's
/// own type parameters, which is the defect this whole lane exists to price.
final class GenericDualAdapter<K1 extends Object, K2 extends Object> implements KeyCodec<(K1, K2)> {
  final DualKeyCodec<K1, K2> _dualCodec;

  /// Wraps [_dualCodec].
  const GenericDualAdapter(this._dualCodec);

  @override
  Object encode((K1, K2) key) => _dualCodec.encode(key.$1, key.$2);

  @override
  (K1, K2) decode(Object rawKey) => _dualCodec.decode(rawKey);
}

/// The same adapter with **no class type parameters**, so its record parameter type is concrete.
/// The one variable separating it from [GenericDualAdapter].
final class ConcreteDualAdapter implements KeyCodec<(int, int)> {
  final DualKeyCodec<int, int> _dualCodec;

  /// Wraps [_dualCodec].
  const ConcreteDualAdapter(this._dualCodec);

  @override
  Object encode((int, int) key) => _dualCodec.encode(key.$1, key.$2);

  @override
  (int, int) decode(Object rawKey) => _dualCodec.decode(rawKey);
}

/// Generic adapter whose parameter is widened to `Object`, moving the record check into an
/// explicit cast. Widening a parameter in an override is legal Dart; it does not help.
final class WidenedDualAdapter<K1 extends Object, K2 extends Object> implements KeyCodec<(K1, K2)> {
  final DualKeyCodec<K1, K2> _dualCodec;

  /// Wraps [_dualCodec].
  const WidenedDualAdapter(this._dualCodec);

  @override
  Object encode(Object key) {
    final (primary, secondary) = key as (K1, K2);

    return _dualCodec.encode(primary, secondary);
  }

  @override
  (K1, K2) decode(Object rawKey) => _dualCodec.decode(rawKey);
}

/// Generic adapter class with a *concrete* record parameter. Fast, and a trap: it keeps a record on
/// the engine boundary while hiding the cost, so the next composite family copies it and the defect
/// returns the moment someone re-parameterises the record.
final class ObjectRecordDualAdapter<K1 extends Object, K2 extends Object>
    implements KeyCodec<(Object, Object)> {
  final DualKeyCodec<K1, K2> _dualCodec;

  /// Wraps [_dualCodec].
  const ObjectRecordDualAdapter(this._dualCodec);

  @override
  Object encode((Object, Object) key) => _dualCodec.encode(key.$1 as K1, key.$2 as K2);

  @override
  (Object, Object) decode(Object rawKey) => _dualCodec.decode(rawKey);
}

/// An engine generic over the **semantic** key, owning its codec: the pre-fix shape.
final class SemanticKeyEngine<T extends Object, K extends Object> {
  final Map<Object, Object?> _store;
  final KeyCodec<K> _keyCodec;

  /// Wires the engine over [_store] with [_keyCodec].
  SemanticKeyEngine(this._store, this._keyCodec);

  /// Reads [key], encoding it through the codec first.
  // Inlined to match the shipped engine's pragma, so the lane prices the same code the package does.
  @pragma('vm:prefer-inline')
  Hit get(K key) {
    final stored = _store[_keyCodec.encode(key)];

    return stored == null ? const Hit(null) : Hit(stored as Payload);
  }
}

/// An engine taking an already-encoded raw key, with no key type parameter: the post-fix shape.
final class RawKeyEngine<T extends Object> {
  final Map<Object, Object?> _store;

  /// Wires the engine over [_store].
  RawKeyEngine(this._store);

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
/// A codec that failed to round-trip would make its lane miss on every op, which reads as a very
/// fast lane rather than as a broken one. That is precisely how a benchmark starts lying, so this
/// is a hard gate rather than a note in the output.
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
  // The single-key lanes read the same store under plain keys, so every lane shares one map and
  // one allocation profile.
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

  // Warm-up pass, then the timed one. AOT has no JIT to warm, but the first pass still faults in
  // the store's pages, and leaving that in the measurement would flatter whichever lane ran first.
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
    // Stamped per record because this lane pins *compiler* behaviour, not library behaviour. If a
    // future SDK teaches AOT to cache this subtype check, these numbers collapse and the reader
    // needs to know which toolchain produced them before concluding anything.
    'sdk': Platform.version,
    // Summed, not xor-ed: an xor over a repeating sample cancels to zero and would hide a lane
    // that measured nothing at all.
    'checksum': checksum,
  });
}

/// The `(primary, secondary)` sample every dual lane walks. Fixed seed, no `Random`, so the
/// sequence is identical across machines as well as across lanes.
List<(int, int)> buildPairs() {
  var seed = sampleSeed;
  int next() => seed = (seed * 1103515245 + 12345) & 0x3FFFFFFF;

  return [for (var i = 0; i < keySampleSize; i++) (next() % 0xFFFF, next() % 0xFFFF)];
}

/// Resolves [lane] to the closure the timed loop calls, or `null` when the name is unknown.
///
/// Each closure returns the found payload's id so the caller can checksum it. The lane's whole
/// wiring is built here, outside the timed window.
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
