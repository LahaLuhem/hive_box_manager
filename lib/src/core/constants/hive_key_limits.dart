/// hive_ce's raw-key domain limits, shared by the write-path corruption gate and (via the test
/// support re-export) the behaviour pins. Release-mode hive_ce enforces neither limit itself:
/// its only guard (`Frame.assertKey`) is assert-stripped there, so out-of-range int keys wrap
/// silently and oversized String keys corrupt the whole box file. That gap is why the gate exists.
abstract final class HiveKeyLimits {
  /// Int keys are unsigned 32-bit; the largest storable int key (hive frames the domain as "range 0 - 0xFFFFFFFF").
  static const maxIntKey = 0xFFFFFFFF;

  /// String keys are capped at this many UTF-8 bytes; one byte more corrupts the box file in release mode
  /// (pinned by the key-constraint suite).
  static const maxStringKeyBytes = 255;
}
