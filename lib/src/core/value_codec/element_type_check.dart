/// Checked up front so a wrong element fails at the read, where the engine can name the key, and not
/// later wherever the list ends up being used.
void checkElementTypes<E extends Object>(Iterable<Object?> elements) {
  if (elements.every((element) => element is E)) return;

  // The cast is what throws, and its error names both types.
  elements.firstWhere((element) => element is! E)! as E;
}
