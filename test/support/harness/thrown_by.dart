import 'dart:async';

/// Use this over `checks`' `throws` when the call might hand back a lazy cast view. `throws` prints what
/// came back inside its own try, and printing that view throws the very `TypeError` the test wants, so
/// a broken read passes.
Future<Object> thrownBy(FutureOr<Object?> Function() act) async {
  try {
    await act();
  } on Object catch (error) {
    return error;
  }

  throw StateError('expected a throw, but the call returned');
}
