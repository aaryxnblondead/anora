import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/journal_entry.dart';

class StorageService {
  StorageService._();

  static final StorageService instance = StorageService._();

  static const String _boxName = 'encrypted_journal';
  static const String _settingsBoxName = 'encrypted_settings';
  static const String _secureKeyName = 'anora_encryption_key';
  static const String _quotesKey = 'home_quotes';
  static const String _quoteIndexKey = 'home_quote_index';
  static const String _unstuckSessionsKey = 'unstuck_sessions';
  static const String _flModelVersionKey = 'fl_downloaded_model_version';
  static const String _flModelB64Key = 'fl_downloaded_model_b64';

  static const List<Map<String, dynamic>> _defaultQuotes = [
    {
      'id': 'q1',
      'text': 'Small steps still move you forward.',
      'author': 'Anora',
      'isFavorite': false,
    },
    {
      'id': 'q2',
      'text': 'Notice the feeling, then notice the breath.',
      'author': 'Anora',
      'isFavorite': false,
    },
    {
      'id': 'q3',
      'text': 'You can be both a work in progress and proud.',
      'author': 'Anora',
      'isFavorite': false,
    },
    {
      'id': 'q4',
      'text': 'Kindness to yourself counts as momentum.',
      'author': 'Anora',
      'isFavorite': false,
    },
    {
      'id': 'q5',
      'text': 'Let today be gentle. That is enough.',
      'author': 'Anora',
      'isFavorite': false,
    },
  ];

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Box<JournalEntry>? _journalBox;
  Box<dynamic>? _settingsBox;

  Box<JournalEntry> get journalBox {
    final box = _journalBox;
    if (box == null) {
      throw StateError('StorageService.init() must be called first.');
    }
    return box;
  }

  Box<dynamic> get settingsBox {
    final box = _settingsBox;
    if (box == null) {
      throw StateError('StorageService.init() must be called first.');
    }
    return box;
  }

  /// Returns a stable device identifier stored in settings.
  /// Generated once and persisted in the encrypted settings box.
  String get deviceId {
    final raw = settingsBox.get('device_id');
    if (raw is String && raw.isNotEmpty) return raw;
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final id = base64UrlEncode(Uint8List.fromList(bytes));
    settingsBox.put('device_id', id);
    return id;
  }

  /// Persist a small federated-learning head weights vector.
  Future<void> saveFlHeadWeights(List<double> weights) async {
    try {
      final encoded = jsonEncode(weights);
      await settingsBox.put('fl_head_weights', encoded);
    } catch (e) {
      debugPrint('⚠️ Failed to save FL head weights: $e');
    }
  }

  /// Load persisted FL head weights if available.
  List<double>? loadFlHeadWeights() {
    final raw = settingsBox.get('fl_head_weights');
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        return decoded.map((e) => (e as num).toDouble()).toList();
      } catch (e) {
        debugPrint('⚠️ Failed to decode FL head weights: $e');
        return null;
      }
    }
    return null;
  }

  /// Persist downloaded FL model bytes as base64 with version metadata.
  Future<void> saveDownloadedFlModel({
    required int version,
    required String base64Model,
  }) async {
    try {
      await settingsBox.put(_flModelVersionKey, version);
      await settingsBox.put(_flModelB64Key, base64Model);
    } catch (e) {
      debugPrint('⚠️ Failed to persist downloaded FL model: $e');
    }
  }

  /// Load persisted downloaded FL model base64 blob, if present.
  String? loadDownloadedFlModelBase64() {
    final raw = settingsBox.get(_flModelB64Key);
    if (raw is String && raw.trim().isNotEmpty) {
      return raw.trim();
    }
    return null;
  }

  /// Load persisted downloaded FL model version, if present.
  int? loadDownloadedFlModelVersion() {
    final raw = settingsBox.get(_flModelVersionKey);
    if (raw is int && raw >= 0) {
      return raw;
    }
    if (raw is num && raw >= 0) {
      return raw.toInt();
    }
    return null;
  }

  /// Remove persisted downloaded FL model blob and version metadata.
  Future<void> clearDownloadedFlModel() async {
    await settingsBox.delete(_flModelVersionKey);
    await settingsBox.delete(_flModelB64Key);
  }

  Future<void> init() async {
    await Hive.initFlutter();

    if (!Hive.isAdapterRegistered(JournalEntryAdapter().typeId)) {
      Hive.registerAdapter(JournalEntryAdapter());
    }

    // Try to open boxes using the stored key. If opening fails (for example
    // because the stored key is corrupt or doesn't match the existing box
    // encryption), clear the persisted key and boxes and retry once so the
    // app can recover instead of crashing on startup.
    Uint8List keyBytes = await _getOrCreateEncryptionKey();
    try {
      _journalBox = await Hive.openBox<JournalEntry>(
        _boxName,
        encryptionCipher: HiveAesCipher(keyBytes),
      );
      _settingsBox = await Hive.openBox<dynamic>(
        _settingsBoxName,
        encryptionCipher: HiveAesCipher(keyBytes),
      );
    } catch (e) {
      // If opening the box failed, remove stored key and any existing box
      // files so we can recreate them with a fresh key. This prevents
      // unrecoverable BadPadding/BadDecrypt errors when a previous key
      // doesn't match the on-disk data.
      try {
        await _secureStorage.delete(key: _secureKeyName);
      } catch (_) {}

      try {
        await Hive.deleteBoxFromDisk(_boxName);
      } catch (_) {}

      try {
        await Hive.deleteBoxFromDisk(_settingsBoxName);
      } catch (_) {}

      // Generate a new key and try again once.
      keyBytes = await _getOrCreateEncryptionKey();
      _journalBox = await Hive.openBox<JournalEntry>(
        _boxName,
        encryptionCipher: HiveAesCipher(keyBytes),
      );
      _settingsBox = await Hive.openBox<dynamic>(
        _settingsBoxName,
        encryptionCipher: HiveAesCipher(keyBytes),
      );
    }
  }

  bool readBoolSetting(String key, {required bool fallback}) {
    return settingsBox.get(key, defaultValue: fallback) as bool;
  }

  Future<void> writeBoolSetting(String key, bool value) async {
    await settingsBox.put(key, value);
  }

  Future<List<Map<String, dynamic>>> loadQuotes() async {
    final raw = settingsBox.get(_quotesKey);
    if (raw is List) {
      return _normalizeQuotes(raw);
    }

    await settingsBox.put(_quotesKey, _defaultQuotes);
    return List<Map<String, dynamic>>.from(_defaultQuotes);
  }

  Future<void> saveQuotes(List<Map<String, dynamic>> quotes) async {
    await settingsBox.put(_quotesKey, quotes);
  }

  Future<int> loadQuoteIndex() async {
    final raw = settingsBox.get(_quoteIndexKey);
    if (raw is int) return raw;
    await settingsBox.put(_quoteIndexKey, 0);
    return 0;
  }

  Future<void> saveQuoteIndex(int index) async {
    await settingsBox.put(_quoteIndexKey, index);
  }

  Future<void> eraseAllData() async {
    await _journalBox?.close();
    await _settingsBox?.close();
    _journalBox = null;
    _settingsBox = null;

    await Hive.deleteBoxFromDisk(_boxName);
    await Hive.deleteBoxFromDisk(_settingsBoxName);
    await _secureStorage.delete(key: _secureKeyName);

    await init();
  }

  /// Persist an Unstuck session summary. Stored as a list of maps under
  /// the `_unstuckSessionsKey` in the settings box.
  Future<void> addUnstuckSession(Map<String, dynamic> session) async {
    final raw = settingsBox.get(_unstuckSessionsKey);
    final List<dynamic> sessions = raw is List ? List<dynamic>.from(raw) : <dynamic>[];
    sessions.add(session);
    await settingsBox.put(_unstuckSessionsKey, sessions);
  }

  /// Read stored Unstuck sessions (may be empty).
  List<Map<String, dynamic>> readUnstuckSessions() {
    final raw = settingsBox.get(_unstuckSessionsKey);
    if (raw is List) {
      try {
        return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList(growable: false);
      } catch (_) {
        return <Map<String, dynamic>>[];
      }
    }
    return <Map<String, dynamic>>[];
  }

  Future<Uint8List> _getOrCreateEncryptionKey() async {
    try {
      final storedKey = await _secureStorage.read(key: _secureKeyName);
      if (storedKey != null) {
        return base64Url.decode(storedKey);
      }
    } catch (e) {
      // Key corrupted or decryption failed - delete and regenerate
      debugPrint('⚠️ Encryption key corrupted, regenerating: $e');
      try {
        await _secureStorage.delete(key: _secureKeyName);
      } catch (deleteError) {
        debugPrint('⚠️ Failed to delete corrupted encryption key: $deleteError');
      }
    }

    final keyBytes = _generateSecureKey();
    try {
      await _secureStorage.write(
        key: _secureKeyName,
        value: base64UrlEncode(keyBytes),
      );
    } catch (writeError) {
      debugPrint('⚠️ Failed to persist regenerated encryption key: $writeError');
    }

    return keyBytes;
  }

  Uint8List _generateSecureKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return Uint8List.fromList(bytes);
  }

  List<Map<String, dynamic>> _normalizeQuotes(List<dynamic> raw) {
    final normalized = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map) {
        final id = item['id']?.toString() ?? '';
        final text = item['text']?.toString() ?? '';
        final author = item['author']?.toString() ?? '';
        final isFavorite = item['isFavorite'] == true;
        if (id.isEmpty || text.isEmpty) continue;
        normalized.add({
          'id': id,
          'text': text,
          'author': author.isEmpty ? 'Anora' : author,
          'isFavorite': isFavorite,
        });
      }
    }

    if (normalized.isEmpty) {
      normalized.addAll(_defaultQuotes);
    }

    return normalized;
  }
}
