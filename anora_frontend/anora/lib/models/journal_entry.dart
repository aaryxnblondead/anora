import 'package:hive/hive.dart';

@HiveType(typeId: 0)
class JournalEntry extends HiveObject {
  JournalEntry({
    required this.id,
    required this.text,
    required this.timestamp,
    required this.moodScore,
    required this.moodPath,
    required this.riskFlags,
  });

  @HiveField(0)
  final String id;

  @HiveField(1)
  final String text;

  @HiveField(2)
  final DateTime timestamp;

  @HiveField(3)
  final double moodScore;

  @HiveField(4)
  final List<String> moodPath;

  @HiveField(5)
  final List<String> riskFlags;
}

class JournalEntryAdapter extends TypeAdapter<JournalEntry> {
  @override
  final int typeId = 0;

  @override
  JournalEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numOfFields; i++)
        reader.readByte(): reader.read(),
    };

    return JournalEntry(
      id: fields[0] as String,
      text: fields[1] as String,
      timestamp: fields[2] as DateTime,
      moodScore: fields[3] as double,
      moodPath: (fields[4] as List?)?.cast<String>() ?? const [],
      riskFlags: (fields[5] as List?)?.cast<String>() ?? const [],
    );
  }

  @override
  void write(BinaryWriter writer, JournalEntry obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.text)
      ..writeByte(2)
      ..write(obj.timestamp)
      ..writeByte(3)
      ..write(obj.moodScore)
      ..writeByte(4)
      ..write(obj.moodPath)
      ..writeByte(5)
      ..write(obj.riskFlags);
  }
}
