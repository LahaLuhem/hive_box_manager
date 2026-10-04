import 'package:hive_ce/hive.dart';

/// Hands a lazy façade its box and counts the opens, so suites can pin open-once behaviour.
final class CountingOpener(final LazyBox<Object?> _box, {final Future<void>? _until}) {
  /// How many times [open] ran.
  var count = 0;

  /// The `openBox` a lazy façade's testing seam takes. Holds back until `until` completes, if given,
  /// so a suite can race effects against an open in flight.
  Future<LazyBox<Object?>> open() async {
    count++;
    if (_until case final until?) await until;

    return _box;
  }
}
