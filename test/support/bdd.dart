/// A thin, zero-dependency Gherkin vocabulary over `package:test`.
///
/// The value here is the shape, not a framework. [feature] and [scenario] make the thing under test
/// and its expected behaviour read as a spec, and [scenarioOutline] drives one of them from a table
/// of named examples so the inputs stay together instead of scattered through the body.
///
/// Copied from the maintainer's `minted` package (`test/support/bdd.dart`). Adapt here as needed, and
/// keep the shape in sync by hand.
library;

import 'dart:async';

import 'package:test/test.dart';

/// Groups the scenarios describing one unit under test. Reads as `Feature: <description>` in the test
/// output.
void feature(String description, void Function() body) => group('Feature: $description', body);

/// One behaviour of the unit under test, as a single test. Reads as `Scenario: <description>`, with
/// [body] carrying the Given/When/Then flow.
void scenario(String description, FutureOr<void> Function() body) =>
    test('Scenario: $description', body);

/// A scenario exercised once per row of an examples table.
///
/// [examples] maps each row's name, which is whatever makes that case interesting, to a record of its
/// inputs and expected outcome. [outline] runs once per row and becomes its own test, so a failure names
/// the row that broke.
void scenarioOutline<Row>(
  String description, {
  required Map<String, Row> examples,
  required FutureOr<void> Function(Row example) outline,
}) => group('Scenario Outline: $description', () {
  for (final MapEntry(key: name, value: row) in examples.entries) {
    test(name, () => outline(row));
  }
});
