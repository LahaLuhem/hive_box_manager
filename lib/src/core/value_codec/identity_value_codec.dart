import 'value_codec.dart';

/// Pass-through codec for plainly-typed boxes: hive's adapters already round-trip [T].
final class IdentityValueCodec<T extends Object> implements ValueCodec<T> {
  /// Const so engines can default to it without an allocation per box.
  const IdentityValueCodec();

  @override
  Object toStorable(T value) => value;

  @override
  T fromStored(Object storedValue) => storedValue as T;
}
