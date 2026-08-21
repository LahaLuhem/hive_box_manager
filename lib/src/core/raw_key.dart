/// @docImport '/src/codec/key/key_codec.dart';
/// @docImport 'raw_key_gate.dart';
library;

/// A key already encoded into hive's raw domain: an `int` in u32, or a `String` of at most 255 UTF-8 bytes.
///
/// Free at run time (it erases to its `Object` representation) and makes the engines' contract a
/// compile error to break: a semantic key is not a [RawKey], so it cannot reach an engine by mistake.
/// That is what keeps a composite key from re-entering through a `KeyCodec<(K1, K2)>` seam, which is
/// what cost `DualKeyBox` ~350 ns per op (`benchmark/key_shape_bench.dart`).
///
/// Encoded is not storable: `ensureStorableRawKey` still gates the write paths.
///
/// Never exported: consumers deal in semantic keys and [KeyCodec]s.
extension type const RawKey(Object value);
