import 'package:test/test.dart';

/// Every event [stream] emits while [act] runs.
///
/// Pumps before and after [act], so a subscription that attaches late and an event that lands late
/// are both caught.
Future<List<E>> recordEvents<E>(Stream<E> stream, Future<void> Function() act) async {
  final events = <E>[];
  final subscription = stream.listen(events.add);
  await pumpEventQueue();

  await act();
  await pumpEventQueue();
  await subscription.cancel();

  return events;
}
