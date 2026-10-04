import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Points hive at a fresh temp dir before each test, then closes it and deletes the dir.
///
/// Call it first in `main`, so the suite's own tear-downs (a view-model's `onUnmount`) still find hive
/// open.
void useTempHive(String prefix) {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(prefix);
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });
}
