/// Central mockito codegen (house rule: generated mocks structure the suite; stateful doubles
/// stay hand-written in `fake_boxes.dart`). Import this file, not `mocks.mocks.dart`.
///
/// The no-op private function below only anchors the codegen annotation: mockito's builder
/// reads element annotations, not library metadata.
library;

import 'package:hive_box_manager/src/core/utils/no_op.dart';
import 'package:hive_ce/hive.dart';
import 'package:mockito/annotations.dart';

export 'mocks.mocks.dart';

/// Codegen anchor only: never called; mockito's builder reads element annotations.
@GenerateNiceMocks([
  MockSpec<HiveInterface>(),
  MockSpec<Box<Object?>>(),
  MockSpec<LazyBox<Object?>>(),
])
// deliberately empty anchor
//ignore: unused_element
void _() => noop();
