import 'package:hive_ce/hive.dart';

import 'typedefs.dart';

abstract class BaseBoxManager<T, I> {
  final String boxKey;
  final T defaultValue;

  final LogCallback? logCallback;

  BaseBoxManager({required this.boxKey, required this.defaultValue, this.logCallback})
    : assert(T == int || T == String, 'Hive index type must be int or String');

  Future<void> init({HiveCipher? encryptionCipher});
}
