// The lifecycle core's acquisition seam: pass-through of hive_ce's pluggables, verified against
// a generated mock of the injected HiveInterface (the 1.x IsolatedHive hinge).
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/core/box_provider.dart';
import 'package:hive_ce/hive.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../../support/bdd.dart';
import '../../support/mocks.dart';

/// AES-256 wants exactly this many key bytes.
const aesKeyBytes = 32;

int _reverseComparator(Object? a, Object? b) => 0;

bool _neverCompact(int entries, int deletedEntries) => false;

void main() {
  late MockHiveInterface hive;
  late BoxProvider provider;

  setUp(() {
    hive = MockHiveInterface();
    provider = BoxProvider(hive: hive);
  });

  feature('BoxProvider', () {
    scenario('opens eager boxes Object?-parameterised with hive defaults filled in', () async {
      final box = MockBox();
      when(
        hive.openBox<Object?>(
          any,
          encryptionCipher: anyNamed('encryptionCipher'),
          keyComparator: anyNamed('keyComparator'),
          compactionStrategy: anyNamed('compactionStrategy'),
          crashRecovery: anyNamed('crashRecovery'),
        ),
      ).thenAnswer((_) async => box);

      final opened = await provider.openEagerBox('users');

      check(identical(opened, box)).isTrue();
      final captured = verify(
        hive.openBox<Object?>(
          captureAny,
          encryptionCipher: captureAnyNamed('encryptionCipher'),
          keyComparator: anyNamed('keyComparator'),
          compactionStrategy: anyNamed('compactionStrategy'),
          crashRecovery: captureAnyNamed('crashRecovery'),
        ),
      ).captured;
      check(captured).deepEquals(['users', null, true]);
    });

    scenario('passes every pluggable through to the eager open untouched', () async {
      final box = MockBox();
      final cipher = HiveAesCipher(List.filled(aesKeyBytes, 7));
      when(
        hive.openBox<Object?>(
          any,
          encryptionCipher: anyNamed('encryptionCipher'),
          keyComparator: anyNamed('keyComparator'),
          compactionStrategy: anyNamed('compactionStrategy'),
          crashRecovery: anyNamed('crashRecovery'),
        ),
      ).thenAnswer((_) async => box);

      await provider.openEagerBox(
        'users',
        cipher: cipher,
        keyComparator: _reverseComparator,
        compactionStrategy: _neverCompact,
        crashRecovery: false,
      );

      final captured = verify(
        hive.openBox<Object?>(
          any,
          encryptionCipher: captureAnyNamed('encryptionCipher'),
          keyComparator: captureAnyNamed('keyComparator'),
          compactionStrategy: captureAnyNamed('compactionStrategy'),
          crashRecovery: captureAnyNamed('crashRecovery'),
        ),
      ).captured;
      check(captured).deepEquals([cipher, _reverseComparator, _neverCompact, false]);
    });

    scenario('opens lazy boxes through the same seam', () async {
      final box = MockLazyBox();
      when(
        hive.openLazyBox<Object?>(
          any,
          encryptionCipher: anyNamed('encryptionCipher'),
          keyComparator: anyNamed('keyComparator'),
          compactionStrategy: anyNamed('compactionStrategy'),
          crashRecovery: anyNamed('crashRecovery'),
        ),
      ).thenAnswer((_) async => box);

      final opened = await provider.openLazyBox('logs');

      check(identical(opened, box)).isTrue();
    });

    scenario('defaults to the global Hive instance when nothing is injected', () {
      check(BoxProvider.new).returnsNormally();
    });
  });
}
