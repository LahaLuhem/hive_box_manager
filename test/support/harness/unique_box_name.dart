/// A box name no earlier test used, since IndexedDB keeps boxes across the tests of a browser session.
String uniqueBoxName(String prefix) => '${prefix}_${DateTime.now().millisecondsSinceEpoch}';
