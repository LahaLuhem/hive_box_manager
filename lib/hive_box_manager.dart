/// Typed, fpdart-first façades over `hive_ce` boxes: no `null`s, lazy effects,
/// ready-made CRUD, purpose-built box variants.
///
/// All four box families are live: `KeyedBox`, `SingleValueBox`,
/// `IterableBox`, and `DualKeyBox` (with reverse queries folded in), each in
/// an eager and a lazy variant, alongside the key-codec seam with its four
/// shipped codecs, the box observer pair, and the typed watch events.
library;

export 'src/box/dual_key/dual_key_box.dart' show DualKeyBox;
export 'src/box/dual_key/lazy_dual_key_box.dart' show LazyDualKeyBox;
export 'src/box/iterable/iterable_box.dart' show IterableBox;
export 'src/box/iterable/lazy_iterable_box.dart' show LazyIterableBox;
export 'src/box/keyed/keyed_box.dart' show KeyedBox;
export 'src/box/keyed/lazy_keyed_box.dart' show LazyKeyedBox;
export 'src/box/single_value/lazy_single_value_box.dart' show LazySingleValueBox;
export 'src/box/single_value/single_value_box.dart' show SingleValueBox;
export 'src/codec/dual/dual_key_codec.dart' show DualKeyCodec;
export 'src/codec/dual/packed_int_dual_codec.dart' show PackedIntDualCodec;
export 'src/codec/dual/string_composite_dual_codec.dart' show StringCompositeDualCodec;
export 'src/codec/key/int_key_codec.dart' show IntKeyCodec;
export 'src/codec/key/key_codec.dart' show KeyCodec;
export 'src/codec/key/string_key_codec.dart' show StringKeyCodec;
export 'src/event/lazy_typed_box_event.dart' show LazyTypedBoxEvent;
export 'src/event/typed_box_event.dart' show TypedBoxEvent;
export 'src/observer/box_observer.dart' show BoxObserver;
export 'src/observer/sinks/printing_box_observer.dart' show PrintingBoxObserver;
