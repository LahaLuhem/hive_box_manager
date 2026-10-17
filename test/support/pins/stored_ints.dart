import 'package:hive_ce/hive.dart';

import '../harness/unique_box_name.dart';
import 'probe_key_limits.dart';

/// Whether a round trip through a double keeps an int, and where hive gave it back unchanged.
typedef IntVerdicts = ({bool survivesDouble, Map<String, bool> unchangedIn});

/// The pins want hive to keep an int exactly when a double does, so a change to how it stores ints
/// fails loudly.
final Map<String, Future<IntVerdicts> Function()> storedInts = {
  '2^53': () => _verdicts(1 << 53),
  '2^53 + 1': () => _verdicts(ProbeKeyLimits.firstWebImpreciseInt),
  '2^53 + 2': () => _verdicts((1 << 53) + 2),
  '-(2^53 + 1)': () => _verdicts(-ProbeKeyLimits.firstWebImpreciseInt),
};

Future<IntVerdicts> _verdicts(int sample) async {
  final boxName = uniqueBoxName('ints');
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

  return (survivesDouble: sample.toDouble().toInt() == sample, unchangedIn: unchangedIn);
}

/// One per path an int takes through hive's encoder.
final _positions =
    <String, ({Object Function(int value) wrap, int Function(Object stored) unwrap})>{
      'on its own': (wrap: (value) => value, unwrap: (stored) => stored as int),
      'in a List<int>': (
        wrap: (value) => <int>[value],
        unwrap: (stored) => (stored as List<Object?>).single! as int,
      ),
      'in a Set<int>': (
        wrap: (value) => <int>{value},
        unwrap: (stored) => (stored as Set<Object?>).single! as int,
      ),
      'inside a dynamic value': (
        wrap: (value) => <Object?>[
          <Object?, Object?>{'id': value},
        ],
        unwrap: (stored) =>
            ((stored as List<Object?>).single! as Map<Object?, Object?>)['id']! as int,
      ),
    };
