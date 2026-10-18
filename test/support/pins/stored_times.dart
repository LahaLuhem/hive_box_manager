import 'package:hive_ce/hive.dart';

import '../harness/unique_box_name.dart';

/// Microseconds inside the range, and whole milliseconds anywhere, which hive keeps exactly.
final Map<String, Future<Map<String, bool>> Function()> keptTimes = {
  'a UTC stamp with microseconds': () => _unchangedIn(DateTime.utc(2026, 10, 3, 12, 0, 0, 0, 1)),
  'a local stamp with microseconds': () => _unchangedIn(DateTime(2026, 10, 3, 12, 0, 0, 0, 999)),
  'the first microsecond of the range': () =>
      _unchangedIn(DateTime.fromMicrosecondsSinceEpoch(1 - _rangeMicros, isUtc: true)),
  'the last microsecond of the range': () =>
      _unchangedIn(DateTime.fromMicrosecondsSinceEpoch(_rangeMicros - 1, isUtc: true)),
  'a stamp past the range, in whole milliseconds': () =>
      _unchangedIn(DateTime.utc(9999, 12, 31, 23, 59, 59, 999)),
  'a span with microseconds': () =>
      _unchangedIn(const Duration(milliseconds: 1500, microseconds: 7)),
  'the longest span that keeps microseconds': () =>
      _unchangedIn(const Duration(microseconds: _rangeMicros - 1)),
  'the longest negative span that keeps microseconds': () =>
      _unchangedIn(const Duration(microseconds: 1 - _rangeMicros)),
  'a span past the range, in whole milliseconds': () =>
      _unchangedIn(const Duration(milliseconds: _rangeMillis)),
};

/// Microseconds past the range, which hive changes.
final Map<String, Future<Map<String, bool>> Function()> changedTimes = {
  'an end-of-time sentinel': () => _unchangedIn(DateTime.parse('9999-12-31T23:59:59.999999Z')),
  'the first microsecond past the range': () =>
      _unchangedIn(DateTime.fromMicrosecondsSinceEpoch(_rangeMicros + 1, isUtc: true)),
  'a span past the range, with microseconds': () =>
      _unchangedIn(const Duration(microseconds: _rangeMicros + 1)),
};

// hive_ce's own cut, 2^43 ms: past it a double has no room for microseconds next to the milliseconds.
const _rangeMillis = 8796093022208;
const _rangeMicros = _rangeMillis * 1000;

Future<Map<String, bool>> _unchangedIn(Object sample) async {
  final boxName = uniqueBoxName('times');
  final box = await Hive.openBox<Object>(boxName);
  await box.putAll({
    for (final MapEntry(:key, :value) in _positions.entries) key: value.wrap(sample),
  });
  await box.close();

  final reopened = await Hive.openBox<Object>(boxName);
  final unchangedIn = {
    for (final MapEntry(:key, :value) in _positions.entries)
      key: value.unwrap(reopened.get(key)!) == sample,
  };
  await reopened.deleteFromDisk();

  return unchangedIn;
}

/// One per way a box holds a time.
final _positions =
    <String, ({Object Function(Object time) wrap, Object? Function(Object stored) unwrap})>{
      'on its own': (wrap: (time) => time, unwrap: (stored) => stored),
      'in a list': (wrap: (time) => [time], unwrap: (stored) => (stored as List<Object?>).single),
      'in a set': (wrap: (time) => {time}, unwrap: (stored) => (stored as Set<Object?>).single),
      'as a map key': (
        wrap: (time) => {time: 0},
        unwrap: (stored) => (stored as Map<Object?, Object?>).keys.single,
      ),
    };
