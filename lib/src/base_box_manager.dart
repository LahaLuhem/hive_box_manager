import 'package:hive_ce/hive.dart';
import 'package:meta/meta.dart';

import 'models.dart';
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

  @protected
  @visibleForOverriding
  Stream<BoxEvent> watchStream();

  // Not visible for exporting via [HiveBoxManager]
  //ignore: use_setters_to_change_properties
  static void assignCallback(LogCallback? logCallback) => _logCallback = logCallback;

  Future<void> init({HiveCipher? encryptionCipher});

  @nonVirtual
  Stream<TypedBoxEvent<T, I>> watch() => watchStream().map(
    (boxEvent) => TypedBoxEvent(
      index: boxEvent.key as I,
      value: boxEvent.value as T,
      deleted: boxEvent.deleted,
    ),
  );
}
