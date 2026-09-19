/// @docImport '/src/codec/key/key_codec.dart';
/// @docImport 'raw_key_gate.dart';
library;

/// A key already encoded into hive's raw domain, so an `int` or a `String` within what hive can store.
///
/// Free at run time, and it makes the engine contract a compile error to break: a semantic key is not
/// a [RawKey], so it cannot reach an engine by accident. That is what stops a composite key sneaking
/// back in through a `KeyCodec<(K1, K2)>` seam, the shape `benchmark/key_shape_bench.dart` shows
/// costing `DualKeyBox` dearly.
///
/// Encoded still isn't storable, so `ensureStorableRawKey` guards the write paths.
///
/// Never exported. Consumers deal in semantic keys and [KeyCodec]s.
extension type const RawKey(Object value);
