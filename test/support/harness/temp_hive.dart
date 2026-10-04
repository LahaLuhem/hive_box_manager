import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

/// Where [useTempHive] pointed hive for the running test.
final class TempHive() {
  late Directory _dir;

  /// The file hive keeps the box named [name] in.
  File boxFile(String name) => File('${_dir.path}/$name.hive');
}

/// Points hive at a fresh temp dir before each test, then closes it and deletes the dir.
///
/// Call it first in `main`, so the suite's own tear-downs still find hive open.
TempHive useTempHive(String prefix) {
  final tempHive = TempHive();

  setUp(() {
    tempHive._dir = Directory.systemTemp.createTempSync(prefix);
    Hive.init(tempHive._dir.path);
  });

  tearDown(() async {
    await Hive.close();
    tempHive._dir.deleteSync(recursive: true);
  });

  return tempHive;
}
