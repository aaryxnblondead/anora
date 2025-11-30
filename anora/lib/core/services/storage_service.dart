import 'package:hive_flutter/hive_flutter.dart';
import '../../models/journal_entry.dart';

class StorageService {
  static const String _boxName = 'journals';

  Future<void> initBox() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox<JournalEntry>(_boxName);
    }
  }

  Future<void> saveEntry(JournalEntry entry) async {
    final box = Hive.box<JournalEntry>(_boxName);
    await box.put(entry.id, entry);
  }

  Future<List<JournalEntry>> getAllEntries() async {
    final box = Hive.box<JournalEntry>(_boxName);
    return box.values.toList().cast<JournalEntry>();
  }

  Future<void> deleteEntry(String id) async {
    final box = Hive.box<JournalEntry>(_boxName);
    await box.delete(id);
  }
}