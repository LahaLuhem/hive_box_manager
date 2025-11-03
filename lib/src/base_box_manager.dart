import 'package:hive_ce/hive.dart';
import 'package:meta/meta.dart';

import 'typedefs.dart';

abstract class BaseBoxManager<T, I extends Object> {
  final String boxKey;
  final T defaultValue;

  @protected
  static late final LogCallback? _logCallback;

  BaseBoxManager({required this.boxKey, required this.defaultValue})
    : assert(I == int || I == String, 'Hive index type must be int or String');

  @protected
  @nonVirtual
  LogCallback? get assignedLogCallback => _logCallback;

  set assignCallback(LogCallback? logCallback) => _logCallback = logCallback;

  Future<void> init({HiveCipher? encryptionCipher});
}
