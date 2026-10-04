import 'package:hive_ce/hive.dart';

/// AES-256 wants exactly this many key bytes.
const _aesKeyBytes = 32;

/// An AES-256 cipher for suites that open an encrypted box.
HiveAesCipher testCipher() => HiveAesCipher(List.filled(_aesKeyBytes, 7));
