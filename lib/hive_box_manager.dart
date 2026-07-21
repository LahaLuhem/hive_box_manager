/// Typed, fpdart-first façades over `hive_ce` boxes: no `null`s, lazy effects,
/// ready-made CRUD, purpose-built box variants.
///
/// The 1.0 surface lands phase by phase. Live today: the `KeyedBox`,
/// `SingleValueBox`, and `IterableBox` families, the key-codec seam with its
/// four shipped codecs, the box observer pair, and the typed watch events. The
/// dual-key family follows.
library;

export 'src/box/iterable_box.dart' show IterableBox;
export 'src/box/keyed_box.dart' show KeyedBox;
export 'src/box/lazy_iterable_box.dart' show LazyIterableBox;
export 'src/box/lazy_keyed_box.dart' show LazyKeyedBox;
export 'src/box/lazy_single_value_box.dart' show LazySingleValueBox;
export 'src/box/single_value_box.dart' show SingleValueBox;
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
