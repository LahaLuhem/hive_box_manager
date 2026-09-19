/// Central mockito codegen. Generated mocks give the suite its structure, and stateful doubles stay
/// hand-written in `fake_boxes.dart`. Import this file, not `mocks.mocks.dart`.
///
/// The no-op below is only there to hang the codegen annotation on, since mockito's builder reads element
/// annotations rather than library metadata.
library;

import 'package:hive_box_manager/src/core/utils/no_op.dart';
import 'package:hive_ce/hive.dart';
import 'package:mockito/annotations.dart';

export 'mocks.mocks.dart';

/// Codegen anchor, never called. Mockito's builder reads element annotations.
@GenerateNiceMocks([
  MockSpec<HiveInterface>(),
  MockSpec<Box<Object?>>(),
  MockSpec<LazyBox<Object?>>(),
])
// deliberately empty anchor
//ignore: unused_element
void _() => noop();
