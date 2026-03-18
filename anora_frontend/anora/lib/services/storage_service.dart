import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

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

  Future<void> init() async {
    await Hive.initFlutter();

    if (!Hive.isAdapterRegistered(JournalEntryAdapter().typeId)) {
      Hive.registerAdapter(JournalEntryAdapter());
    }

    final keyBytes = await _getOrCreateEncryptionKey();
    _journalBox = await Hive.openBox<JournalEntry>(
      _boxName,
      encryptionCipher: HiveAesCipher(keyBytes),
    );
    _settingsBox = await Hive.openBox<dynamic>(
      _settingsBoxName,
      encryptionCipher: HiveAesCipher(keyBytes),
    );
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

  Future<Uint8List> _getOrCreateEncryptionKey() async {
    final storedKey = await _secureStorage.read(key: _secureKeyName);
    if (storedKey != null) {
      return base64Url.decode(storedKey);
    }

    final keyBytes = _generateSecureKey();
    await _secureStorage.write(
      key: _secureKeyName,
      value: base64UrlEncode(keyBytes),
    );

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
