import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';

// Using only primitive types (String) so no Hive TypeAdapter is needed.

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationDocumentsDirectory();
  Hive.init(dir.path);

  // Optional: enable library-level logging
  assignManagerLogCallback((msg) => debugPrint('[HiveBoxManager] $msg'));

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Hive Box Manager Example',
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
    home: const MyHomePage(),
  );
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _logNotifier = ValueNotifier<List<String>>(const []);

  void _addLog(String msg) => _logNotifier.value = [msg, ..._logNotifier.value];

  void _clearLog() => _logNotifier.value = const [];

  // ─────────────────────────────────────────────
  // Dialog helpers
  // ─────────────────────────────────────────────
  static final _random = Random();

  Future<({int key, String value})?> _askIntKeyValue() async {
    final result = await showDialog<({String key, String value})>(
      context: context,
      builder: (_) => const KeyValueInputDialog(keyLabel: 'Key (int)', valueLabel: 'Value'),
    );
    if (result == null) return null;
    final parsed = int.tryParse(result.key);
    if (parsed == null) {
      _addLog('⚠️ Invalid int key: "${result.key}"');

      return null;
    }

    return (key: parsed, value: result.value);
  }

  Future<({String key, String value})?> _askStringKeyValue() =>
      showDialog<({String key, String value})>(
        context: context,
        builder: (_) => const KeyValueInputDialog(keyLabel: 'Key', valueLabel: 'Value'),
      );

  Future<int?> _askIntKey() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => const SingleInputDialog(label: 'Key (int)'),
    );
    if (result == null) return null;
    final parsed = int.tryParse(result);
    if (parsed == null) {
      _addLog('⚠️ Invalid int key: "$result"');

      return null;
    }

    return parsed;
  }

  Future<String?> _askStringKey() => showDialog<String>(
    context: context,
    builder: (_) => const SingleInputDialog(label: 'Key'),
  );

  Future<String?> _askValue() => showDialog<String>(
    context: context,
    builder: (_) => const SingleInputDialog(label: 'Value'),
  );

  Future<int?> _askCount() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => const SingleInputDialog(label: 'Count', keyboardType: TextInputType.number),
    );
    if (result == null) return null;
    final parsed = int.tryParse(result);
    if (parsed == null || parsed <= 0) {
      _addLog('⚠️ Invalid count: "$result"');

      return null;
    }

    return parsed;
  }

  static String _randomWord() {
    const words = [
      'alpha',
      'bravo',
      'charlie',
      'delta',
      'echo',
      'foxtrot',
      'golf',
      'hotel',
      'india',
      'juliet',
      'kilo',
      'lima',
    ];

    return words[_random.nextInt(words.length)];
  }

  // ── 1. BoxManager<String, int>  (eager, int keys) ──
  final _eagerBox = BoxManager<String, int>(boxKey: 'eager_users', defaultValue: '');
  var _eagerInitialized = false;

  // ── 2. LazyBoxManager<String, String>  (lazy, string keys) ──
  final _lazyBox = LazyBoxManager<String, String>(boxKey: 'lazy_settings', defaultValue: '<none>');
  var _lazyInitialized = false;

  // ── 3. SingleIndexBoxManager<String>  (eager, single value) ──
  final _singleBox = SingleIndexBoxManager<String>(boxKey: 'app_theme', defaultValue: 'light');
  var _singleInitialized = false;

  // ── 4. SingleIndexLazyBoxManager<String>  (lazy, single value) ──
  final _singleLazyBox = SingleIndexLazyBoxManager<String>(boxKey: 'auth_token', defaultValue: '');
  var _singleLazyInitialized = false;

  // ── 5. Encrypted LazyBoxManager (lazy + encryption) ──
  final _encryptedBox = LazyBoxManager<String, int>(boxKey: 'encrypted_notes', defaultValue: '');
  var _encryptedInitialized = false;
  late final List<int> _encryptionKey;

  @override
  void dispose() {
    _logNotifier.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // Eager BoxManager operations
  // ─────────────────────────────────────────────
  Future<void> _initEager() async {
    await _eagerBox.init();
    _eagerInitialized = true;
    _addLog('✅ BoxManager<String,int> initialized');
  }

  Future<void> _eagerPut() async {
    if (!_eagerInitialized) return _addLog('⚠️ Init BoxManager first!');
    final input = await _askIntKeyValue();
    if (input == null) return;
    await _eagerBox.put(index: input.key, value: input.value).run();
    _addLog('📝 Eager put: key ${input.key} → "${input.value}"');
  }

  Future<void> _eagerGet() async {
    if (!_eagerInitialized) return _addLog('⚠️ Init BoxManager first!');
    final key = await _askIntKey();
    if (key == null) return;
    final v = _eagerBox.get(key);
    _addLog('📖 Eager get: key $key = "$v"');
  }

  void _eagerGetAll() {
    if (!_eagerInitialized) return _addLog('⚠️ Init BoxManager first!');
    final all = _eagerBox.getAll().toList();
    _addLog('📖 Eager getAll (${all.length}): $all');
  }

  Future<void> _eagerDelete() async {
    if (!_eagerInitialized) return _addLog('⚠️ Init BoxManager first!');
    final key = await _askIntKey();
    if (key == null) return;
    await _eagerBox.delete(key).run();
    _addLog('🗑️ Eager delete: key $key removed');
  }

  Future<void> _eagerClear() async {
    if (!_eagerInitialized) return _addLog('⚠️ Init BoxManager first!');
    await _eagerBox.clear().run();
    _addLog('🧹 Eager clear: all entries removed');
  }

  Future<void> _eagerUpsert() async {
    if (!_eagerInitialized) return _addLog('⚠️ Init BoxManager first!');
    final key = await _askIntKey();
    if (key == null) return;
    await _eagerBox.upsert(index: key, boxUpdater: (current) => '${current}_updated').run();
    _addLog('🔄 Eager upsert: key $key → "${_eagerBox.get(key)}"');
  }

  Future<void> _eagerGenerate() async {
    if (!_eagerInitialized) return _addLog('⚠️ Init BoxManager first!');
    final count = await _askCount();
    if (count == null) return;
    for (var i = 0; i < count; i++) {
      await _eagerBox.put(index: i, value: '${_randomWord()}_$i').run();
    }
    _addLog('🎲 Eager generate: $count random entries added (keys 0..${count - 1})');
  }

  // ─────────────────────────────────────────────
  // Lazy BoxManager operations
  // ─────────────────────────────────────────────
  Future<void> _initLazy() async {
    await _lazyBox.init();
    _lazyInitialized = true;
    _addLog('✅ LazyBoxManager<String,String> initialized');
  }

  Future<void> _lazyPut() async {
    if (!_lazyInitialized) return _addLog('⚠️ Init LazyBoxManager first!');
    final input = await _askStringKeyValue();
    if (input == null) return;
    await _lazyBox.put(index: input.key, value: input.value).run();
    _addLog('📝 Lazy put: "${input.key}" → "${input.value}"');
  }

  Future<void> _lazyGet() async {
    if (!_lazyInitialized) return _addLog('⚠️ Init LazyBoxManager first!');
    final key = await _askStringKey();
    if (key == null) return;
    final v = await _lazyBox.get(key).run();
    _addLog('📖 Lazy get: "$key" = "$v"');
  }

  Future<void> _lazyGetAll() async {
    if (!_lazyInitialized) return _addLog('⚠️ Init LazyBoxManager first!');
    final all = await _lazyBox.getAll().run();
    _addLog('📖 Lazy getAll (${all.length}): $all');
  }

  Future<void> _lazyDelete() async {
    if (!_lazyInitialized) return _addLog('⚠️ Init LazyBoxManager first!');
    final key = await _askStringKey();
    if (key == null) return;
    await _lazyBox.delete(key).run();
    _addLog('🗑️ Lazy delete: "$key" removed');
  }

  Future<void> _lazyClear() async {
    if (!_lazyInitialized) return _addLog('⚠️ Init LazyBoxManager first!');
    await _lazyBox.clear().run();
    _addLog('🧹 Lazy clear: all entries removed');
  }

  Future<void> _lazyUpsert() async {
    if (!_lazyInitialized) return _addLog('⚠️ Init LazyBoxManager first!');
    final key = await _askStringKey();
    if (key == null) return;
    await _lazyBox.upsert(index: key, boxUpdater: (current) => '${current}_v2').run();
    final updated = await _lazyBox.get(key).run();
    _addLog('🔄 Lazy upsert: "$key" → "$updated"');
  }

  Future<void> _lazyGenerate() async {
    if (!_lazyInitialized) return _addLog('⚠️ Init LazyBoxManager first!');
    final count = await _askCount();
    if (count == null) return;
    for (var i = 0; i < count; i++) {
      final key = '${_randomWord()}_$i';
      await _lazyBox.put(index: key, value: '${_randomWord()}_value').run();
    }
    _addLog('🎲 Lazy generate: $count random entries added');
  }

  // ─────────────────────────────────────────────
  // SingleIndexBoxManager operations
  // ─────────────────────────────────────────────
  Future<void> _initSingle() async {
    await _singleBox.init();
    _singleInitialized = true;
    _addLog('✅ SingleIndexBoxManager initialized');
  }

  Future<void> _singlePut() async {
    if (!_singleInitialized) return _addLog('⚠️ Init SingleIndexBoxManager first!');
    final value = await _askValue();
    if (value == null) return;
    await _singleBox.put(value: value).run();
    _addLog('📝 Single put: value → "$value"');
  }

  void _singleGet() {
    if (!_singleInitialized) return _addLog('⚠️ Init SingleIndexBoxManager first!');
    final v = _singleBox.get();
    _addLog('📖 Single get: "$v"');
  }

  Future<void> _singleUpsert() async {
    if (!_singleInitialized) return _addLog('⚠️ Init SingleIndexBoxManager first!');
    await _singleBox.upsert(boxUpdater: (current) => current == 'dark' ? 'light' : 'dark').run();
    _addLog('🔄 Single upsert (toggle): "${_singleBox.get()}"');
  }

  Future<void> _singleClear() async {
    if (!_singleInitialized) return _addLog('⚠️ Init SingleIndexBoxManager first!');
    await _singleBox.clear().run();
    _addLog('🧹 Single clear: value reset to default');
  }

  // ─────────────────────────────────────────────
  // SingleIndexLazyBoxManager operations
  // ─────────────────────────────────────────────
  Future<void> _initSingleLazy() async {
    await _singleLazyBox.init();
    _singleLazyInitialized = true;
    _addLog('✅ SingleIndexLazyBoxManager initialized');
  }

  Future<void> _singleLazyPut() async {
    if (!_singleLazyInitialized) return _addLog('⚠️ Init SingleIndexLazyBoxManager first!');
    final value = await _askValue();
    if (value == null) return;
    await _singleLazyBox.put(value: value).run();
    _addLog('📝 SingleLazy put: "$value"');
  }

  Future<void> _singleLazyGet() async {
    if (!_singleLazyInitialized) return _addLog('⚠️ Init SingleIndexLazyBoxManager first!');
    final v = await _singleLazyBox.get().run();
    _addLog('📖 SingleLazy get: "$v"');
  }

  Future<void> _singleLazyDelete() async {
    if (!_singleLazyInitialized) return _addLog('⚠️ Init SingleIndexLazyBoxManager first!');
    await _singleLazyBox.delete().run();
    _addLog('🗑️ SingleLazy delete: value removed');
  }

  Future<void> _singleLazyClear() async {
    if (!_singleLazyInitialized) return _addLog('⚠️ Init SingleIndexLazyBoxManager first!');
    await _singleLazyBox.clear().run();
    _addLog('🧹 SingleLazy clear: value reset');
  }

  // ─────────────────────────────────────────────
  // Encrypted LazyBoxManager operations
  // ─────────────────────────────────────────────
  Future<void> _initEncrypted() async {
    _encryptionKey = Hive.generateSecureKey();
    await _encryptedBox.init(encryptionCipher: HiveAesCipher(_encryptionKey));
    _encryptedInitialized = true;
    _addLog('✅ Encrypted LazyBoxManager initialized (AES-256)');
  }

  Future<void> _encryptedPut() async {
    if (!_encryptedInitialized) return _addLog('⚠️ Init Encrypted box first!');
    final input = await _askIntKeyValue();
    if (input == null) return;
    await _encryptedBox.put(index: input.key, value: input.value).run();
    _addLog('📝 Encrypted put: key ${input.key} → "${input.value}"');
  }

  Future<void> _encryptedGet() async {
    if (!_encryptedInitialized) return _addLog('⚠️ Init Encrypted box first!');
    final key = await _askIntKey();
    if (key == null) return;
    final v = await _encryptedBox.get(key).run();
    _addLog('📖 Encrypted get: key $key = "$v"');
  }

  Future<void> _encryptedClear() async {
    if (!_encryptedInitialized) return _addLog('⚠️ Init Encrypted box first!');
    await _encryptedBox.clear().run();
    _addLog('🧹 Encrypted clear: all entries removed');
  }

  Future<void> _encryptedGenerate() async {
    if (!_encryptedInitialized) return _addLog('⚠️ Init Encrypted box first!');
    final count = await _askCount();
    if (count == null) return;
    for (var i = 0; i < count; i++) {
      await _encryptedBox.put(index: i, value: 'secret_${_randomWord()}_$i').run();
    }
    _addLog('🎲 Encrypted generate: $count random entries added (keys 0..${count - 1})');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      title: const Text('Hive Box Manager Example'),
      actions: [
        IconButton(
          icon: const Icon(Icons.delete_sweep),
          tooltip: 'Clear log',
          onPressed: _clearLog,
        ),
      ],
    ),
    body: Column(
      children: [
        // ── Operation buttons (scrollable) ──
        Expanded(
          flex: 3,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              ManagerSection(
                title: '1. BoxManager<String, int>  (eager)',
                subtitle: 'Requires explicit init(). Synchronous reads.',
                children: [
                  ActionButton(label: 'Init', onPressed: _initEager),
                  ActionButton(label: 'Put', onPressed: _eagerPut),
                  ActionButton(label: 'Get', onPressed: _eagerGet),
                  ActionButton(label: 'Get All', onPressed: _eagerGetAll),
                  ActionButton(label: 'Upsert', onPressed: _eagerUpsert),
                  ActionButton(label: 'Delete', onPressed: _eagerDelete),
                  ActionButton(label: 'Generate N', onPressed: _eagerGenerate),
                  ActionButton(label: 'Clear', onPressed: _eagerClear),
                ],
              ),
              ManagerSection(
                title: '2. LazyBoxManager<String, String>  (lazy)',
                subtitle: 'Requires init(). Async reads via Task.',
                children: [
                  ActionButton(label: 'Init', onPressed: _initLazy),
                  ActionButton(label: 'Put', onPressed: _lazyPut),
                  ActionButton(label: 'Get', onPressed: _lazyGet),
                  ActionButton(label: 'Get All', onPressed: _lazyGetAll),
                  ActionButton(label: 'Upsert', onPressed: _lazyUpsert),
                  ActionButton(label: 'Delete', onPressed: _lazyDelete),
                  ActionButton(label: 'Generate N', onPressed: _lazyGenerate),
                  ActionButton(label: 'Clear', onPressed: _lazyClear),
                ],
              ),
              ManagerSection(
                title: '3. SingleIndexBoxManager<String>  (eager, single)',
                subtitle: 'One value per box. Requires init().',
                children: [
                  ActionButton(label: 'Init', onPressed: _initSingle),
                  ActionButton(label: 'Put', onPressed: _singlePut),
                  ActionButton(label: 'Get', onPressed: _singleGet),
                  ActionButton(label: 'Upsert (toggle)', onPressed: _singleUpsert),
                  ActionButton(label: 'Clear', onPressed: _singleClear),
                ],
              ),
              ManagerSection(
                title: '4. SingleIndexLazyBoxManager<String>  (lazy, single)',
                subtitle: 'One value per box. Requires init().',
                children: [
                  ActionButton(label: 'Init', onPressed: _initSingleLazy),
                  ActionButton(label: 'Put', onPressed: _singleLazyPut),
                  ActionButton(label: 'Get', onPressed: _singleLazyGet),
                  ActionButton(label: 'Delete', onPressed: _singleLazyDelete),
                  ActionButton(label: 'Clear', onPressed: _singleLazyClear),
                ],
              ),
              ManagerSection(
                title: '5. Encrypted LazyBoxManager<String, int>',
                subtitle: 'HiveAesCipher passed to init(). Encrypted at rest.',
                children: [
                  ActionButton(label: 'Init (generate key)', onPressed: _initEncrypted),
                  ActionButton(label: 'Put', onPressed: _encryptedPut),
                  ActionButton(label: 'Get', onPressed: _encryptedGet),
                  ActionButton(label: 'Generate N', onPressed: _encryptedGenerate),
                  ActionButton(label: 'Clear', onPressed: _encryptedClear),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // ── Log output ──
        Expanded(flex: 2, child: LogPanel(logNotifier: _logNotifier)),
      ],
    ),
  );
}

class ManagerSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  const ManagerSection({
    required this.title,
    required this.subtitle,
    required this.children,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: children),
        ],
      ),
    ),
  );
}

class ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const ActionButton({required this.label, required this.onPressed, super.key});

  @override
  Widget build(BuildContext context) => ElevatedButton(
    onPressed: onPressed,
    style: ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      textStyle: const TextStyle(fontSize: 12),
    ),
    child: Text(label),
  );
}

class LogPanel extends StatelessWidget {
  final ValueListenable<List<String>> logNotifier;

  const LogPanel({required this.logNotifier, super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<String>>(
    valueListenable: logNotifier,
    builder: (_, log, _) => Container(
      color: Colors.grey.shade900,
      width: double.infinity,
      child: log.isEmpty
          ? const Center(
              child: Text(
                'Tap buttons above to see results here',
                style: TextStyle(color: Colors.white54),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: log.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  log[i],
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
    ),
  );
}

// ─────────────────────────────────────────────
// Input dialog widgets
// ─────────────────────────────────────────────

class KeyValueInputDialog extends StatefulWidget {
  const KeyValueInputDialog({required this.keyLabel, required this.valueLabel, super.key});

  final String keyLabel;
  final String valueLabel;

  @override
  State<KeyValueInputDialog> createState() => _KeyValueInputDialogState();
}

class _KeyValueInputDialogState extends State<KeyValueInputDialog> {
  final _keyCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();

  @override
  void dispose() {
    _keyCtrl.dispose();
    _valueCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final key = _keyCtrl.text.trim();
    final value = _valueCtrl.text.trim();
    if (key.isEmpty || value.isEmpty) return;
    Navigator.of(context).pop((key: key, value: value));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Enter key-value pair'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _keyCtrl,
          decoration: InputDecoration(labelText: widget.keyLabel),
          autofocus: true,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _valueCtrl,
          decoration: InputDecoration(labelText: widget.valueLabel),
          onSubmitted: (_) => _submit(),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      ElevatedButton(onPressed: _submit, child: const Text('OK')),
    ],
  );
}

class SingleInputDialog extends StatefulWidget {
  const SingleInputDialog({required this.label, this.keyboardType, super.key});

  final String label;
  final TextInputType? keyboardType;

  @override
  State<SingleInputDialog> createState() => _SingleInputDialogState();
}

class _SingleInputDialogState extends State<SingleInputDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Enter ${widget.label.toLowerCase()}'),
    content: TextField(
      controller: _ctrl,
      decoration: InputDecoration(labelText: widget.label),
      keyboardType: widget.keyboardType,
      autofocus: true,
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      ElevatedButton(onPressed: _submit, child: const Text('OK')),
    ],
  );
}
