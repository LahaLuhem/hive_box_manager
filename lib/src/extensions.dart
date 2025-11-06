import 'package:fpdart/fpdart.dart';

extension TaskVoidExtension on Task<void> {
  Task<Unit> mapToUnit() => map((_) => unit);
}

extension TaskListExtension on Task<List<void>> {
  Task<Unit> mapToUnit() => map((_) => unit);
}

extension TaskUnitExtension on Task<Unit> {
  Task<Unit> attachAction(void Function() action) => map((u) {
    action.call();

    return u;
  });
}
