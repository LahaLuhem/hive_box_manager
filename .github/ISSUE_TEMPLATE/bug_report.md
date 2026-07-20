---
name: Bug report
about: A Manager returns the wrong value, loses data, or otherwise misbehaves against a box
title: "[BUG]"
labels: ''
assignees: ''

---

**Which Manager**
e.g. `BoxManager`, `LazyBoxManager`, a single-index / collection / dual-index variant.

**What happened**
A clear and concise description of the bug.

**Minimal reproduction**
The Manager setup and the exact call, plus what you got back:

```dart
final box = LazyBoxManager<String, int>(boxKey: 'demo', defaultValue: '<none>');
await box.init();
await box.put(index: 1, value: 'a').run();

final result = await box.get(1).run();
// expected: 'a'
// got: ...
```

**Expected behaviour**
What should the Manager have returned or stored?

**Environment**
 - `hive_box_manager` version: [e.g. 0.1.0]
 - `hive_ce` version: [from pubspec.lock]
 - Dart SDK: [`dart --version`]
 - Runtime: [Flutter / Dart server / CLI / web]

**Additional context**
Anything else worth knowing (is it eager vs lazy, does it reproduce with a fresh box, etc.).
