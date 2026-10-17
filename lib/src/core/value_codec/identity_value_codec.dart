import 'package:meta/meta.dart';

import 'int_check.dart';
import 'value_codec.dart';

/// [IdentityValueCodec] for a [T], checking ints on the way to disk when a [T] can hold one.
@internal
IdentityValueCodec<T> identityCodecFor<T extends Object>() => switch (intCheckFor<T>()) {
  final intCheck? => _IntCheckingValueCodec<T>(intCheck),
  null => IdentityValueCodec<T>(),
};

/// Pass-through codec for plainly-typed boxes: hive's adapters already round-trip [T].
@internal
final class const IdentityValueCodec<T extends Object>() implements ValueCodec<T> {
  /// Const, since it holds nothing.
  this;

  @override
  Object toStorable(T value) => value;

  @override
  @nonVirtual
  T fromStored(Object storedValue) => storedValue as T;
}

final class _IntCheckingValueCodec<T extends Object>(final IntCheck _intCheck)
    extends IdentityValueCodec<T> {
  @override
  Object toStorable(T value) {
    _intCheck(value);

    return value;
  }
}
