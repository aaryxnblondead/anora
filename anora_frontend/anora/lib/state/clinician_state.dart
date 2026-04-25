import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../services/clinician_crypto_service.dart';
import '../services/storage_service.dart';
import '../utils/env.dart';

const _clinicianReportsCacheKey = 'clinician_reports_cache';

class ClinicianProfile {
  const ClinicianProfile({
    required this.name,
    required this.credentials,
    required this.clinicianId,
    required this.publicKeyPem,
    required this.hasPrivateKey,
  });

  final String name;
  final String credentials;
  final String clinicianId;
  final String publicKeyPem;
  final bool hasPrivateKey;

  factory ClinicianProfile.fromStorage() {
    final box = StorageService.instance.settingsBox;
    final publicKeyPem = (box.get('clinician_public_key_pem') as String?) ?? '';
    final privateKeyPem = (box.get('clinician_private_key_pem') as String?) ?? '';

    return ClinicianProfile(
      name: (box.get('clinician_name') as String?) ?? '',
      credentials: (box.get('clinician_credentials') as String?) ?? '',
      clinicianId: (box.get('clinician_id') as String?) ?? '',
      publicKeyPem: publicKeyPem,
      hasPrivateKey: privateKeyPem.isNotEmpty,
    );
  }
}

class PatientRecord {
  const PatientRecord({
    required this.patientLabel,
    required this.reportId,
    required this.receivedAt,
    required this.clinicianId,
    required this.entryCount,
    required this.avgMoodScore,
    required this.riskFlagCounts,
    required this.topEmotion,
    required this.isDecrypted,
    required this.encryptedKeyB64,
    required this.encryptedPayload,
    required this.riskTrend,
  });

  final String patientLabel;
  final String reportId;
  final DateTime receivedAt;
  final String clinicianId;
  final int? entryCount;
  final double? avgMoodScore;
  final Map<String, int>? riskFlagCounts;
  final String? topEmotion;
  final bool isDecrypted;
  final String? encryptedKeyB64;
  final Map<String, String>? encryptedPayload;
  final List<int>? riskTrend;

  PatientRecord copyWith({
    String? patientLabel,
    String? reportId,
    DateTime? receivedAt,
    String? clinicianId,
    int? entryCount,
    double? avgMoodScore,
    Map<String, int>? riskFlagCounts,
    String? topEmotion,
    bool? isDecrypted,
    String? encryptedKeyB64,
    Map<String, String>? encryptedPayload,
    List<int>? riskTrend,
  }) {
    return PatientRecord(
      patientLabel: patientLabel ?? this.patientLabel,
      reportId: reportId ?? this.reportId,
      receivedAt: receivedAt ?? this.receivedAt,
      clinicianId: clinicianId ?? this.clinicianId,
      entryCount: entryCount ?? this.entryCount,
      avgMoodScore: avgMoodScore ?? this.avgMoodScore,
      riskFlagCounts: riskFlagCounts ?? this.riskFlagCounts,
      topEmotion: topEmotion ?? this.topEmotion,
      isDecrypted: isDecrypted ?? this.isDecrypted,
      encryptedKeyB64: encryptedKeyB64 ?? this.encryptedKeyB64,
      encryptedPayload: encryptedPayload ?? this.encryptedPayload,
      riskTrend: riskTrend ?? this.riskTrend,
    );
  }

  factory PatientRecord.fromJson(Map<String, dynamic> json) {
    final riskMap = <String, int>{};
    final rawRisk = json['riskFlagCounts'];
    if (rawRisk is Map) {
      for (final entry in rawRisk.entries) {
        final value = entry.value;
        if (value is int) {
          riskMap[entry.key.toString()] = value;
        } else if (value is num) {
          riskMap[entry.key.toString()] = value.toInt();
        }
      }
    }

    final encryptedMap = <String, String>{};
    final rawEncryptedPayload = json['encryptedPayload'];
    if (rawEncryptedPayload is Map) {
      for (final entry in rawEncryptedPayload.entries) {
        final value = entry.value;
        if (value != null) {
          encryptedMap[entry.key.toString()] = value.toString();
        }
      }
    }

    final trend = <int>[];
    final rawTrend = json['riskTrend'];
    if (rawTrend is List) {
      for (final value in rawTrend) {
        if (value is int) {
          trend.add(value);
        } else if (value is num) {
          trend.add(value.toInt());
        }
      }
    }

    return PatientRecord(
      patientLabel: (json['patientLabel'] as String?) ?? 'Patient',
      reportId: (json['reportId'] as String?) ?? '',
      receivedAt: DateTime.tryParse((json['receivedAt'] as String?) ?? '') ?? DateTime.now(),
      clinicianId: (json['clinicianId'] as String?) ?? '',
      entryCount: json['entryCount'] as int?,
      avgMoodScore: (json['avgMoodScore'] as num?)?.toDouble(),
      riskFlagCounts: riskMap.isEmpty ? null : riskMap,
      topEmotion: json['topEmotion'] as String?,
      isDecrypted: json['isDecrypted'] == true,
      encryptedKeyB64: json['encryptedKeyB64'] as String?,
      encryptedPayload: encryptedMap.isEmpty ? null : encryptedMap,
      riskTrend: trend.isEmpty ? null : trend,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'patientLabel': patientLabel,
      'reportId': reportId,
      'receivedAt': receivedAt.toIso8601String(),
      'clinicianId': clinicianId,
      'entryCount': entryCount,
      'avgMoodScore': avgMoodScore,
      'riskFlagCounts': riskFlagCounts,
      'topEmotion': topEmotion,
      'isDecrypted': isDecrypted,
      'encryptedKeyB64': encryptedKeyB64,
      'encryptedPayload': encryptedPayload,
      'riskTrend': riskTrend,
    };
  }
}

class ClinicianReportsState {
  const ClinicianReportsState({
    this.records = const <PatientRecord>[],
    this.isLoading = false,
    this.error,
  });

  final List<PatientRecord> records;
  final bool isLoading;
  final String? error;

  ClinicianReportsState copyWith({
    List<PatientRecord>? records,
    bool? isLoading,
    String? error,
  }) {
    return ClinicianReportsState(
      records: records ?? this.records,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

final clinicianReportsProvider =
    StateNotifierProvider<ClinicianReportsNotifier, ClinicianReportsState>(
  (ref) => ClinicianReportsNotifier(StorageService.instance),
);

class ClinicianReportsNotifier extends StateNotifier<ClinicianReportsState> {
  ClinicianReportsNotifier(this._storage) : super(const ClinicianReportsState()) {
    loadFromLocalCache();
  }

  final StorageService _storage;

  void loadFromLocalCache() {
    final raw = _storage.settingsBox.get(_clinicianReportsCacheKey);
    if (raw == null) {
      state = state.copyWith(records: <PatientRecord>[], isLoading: false, error: null);
      return;
    }

    try {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is! List) {
        state = state.copyWith(error: 'Invalid local reports cache format.');
        return;
      }

      final records = decoded
          .whereType<Map>()
          .map((map) => PatientRecord.fromJson(Map<String, dynamic>.from(map)))
          .toList(growable: false)
        ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));

      state = state.copyWith(records: records, isLoading: false, error: null);
    } catch (error) {
      state = state.copyWith(error: 'Could not parse reports cache: $error', isLoading: false);
    }
  }

  Future<void> fetchReport(String reportId) async {
    final id = reportId.trim();
    if (id.isEmpty) {
      state = state.copyWith(error: 'Report ID is required.');
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      // TODO: Enforce clinician JWT auth on GET /reports backend endpoint.
      final response = await http.get(Uri.parse('${Env.apiBaseUrl}/reports/$id'));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        throw Exception('Unexpected response payload.');
      }

      final lockedBox = body['locked_box'];
      if (lockedBox is! Map<String, dynamic>) {
        throw Exception('Missing locked_box in response.');
      }

      final encryptedKeyB64 = lockedBox['encrypted_key'];
      final encryptedPayloadRaw = lockedBox['encrypted_payload'];
      if (encryptedKeyB64 is! String || encryptedPayloadRaw is! Map<String, dynamic>) {
        throw Exception('Invalid encrypted payload shape.');
      }

      final encryptedPayload = <String, String>{};
      for (final entry in encryptedPayloadRaw.entries) {
        encryptedPayload[entry.key] = entry.value.toString();
      }

      final clinicianId = (body['clinician_id'] as String?) ??
          ((_storage.settingsBox.get('clinician_id') as String?) ?? '');
      final receivedAt = DateTime.tryParse((body['created_at'] as String?) ?? '') ?? DateTime.now();

      final existingIndex = state.records.indexWhere((record) => record.reportId == id);
      final baseRecord = PatientRecord(
        patientLabel: _defaultPatientLabel(existingIndex >= 0 ? existingIndex : state.records.length),
        reportId: id,
        receivedAt: receivedAt,
        clinicianId: clinicianId,
        entryCount: null,
        avgMoodScore: null,
        riskFlagCounts: null,
        topEmotion: null,
        isDecrypted: false,
        encryptedKeyB64: encryptedKeyB64,
        encryptedPayload: encryptedPayload,
        riskTrend: null,
      );

      final updated = [...state.records];
      if (existingIndex >= 0) {
        updated[existingIndex] = baseRecord;
      } else {
        updated.add(baseRecord);
      }
      updated.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));

      state = state.copyWith(records: updated, isLoading: false, error: null);
      await _persistCache(updated);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: 'Could not fetch report: $error');
      rethrow;
    }
  }

  Future<void> decryptRecord(String reportId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final index = state.records.indexWhere((record) => record.reportId == reportId);
      if (index < 0) {
        throw Exception('Report not found in local state.');
      }

      final record = state.records[index];
      final encryptedKey = record.encryptedKeyB64;
      final encryptedPayload = record.encryptedPayload;
      if (encryptedKey == null || encryptedPayload == null) {
        throw Exception('Encrypted payload is unavailable for this report.');
      }

      // TODO: Add patient consent confirmation before decrypting each report.
      final decryptedJson = ClinicianCryptoService.instance.decryptReportPayload(
        encryptedKeyB64: encryptedKey,
        encryptedPayload: encryptedPayload,
      );

      final decoded = jsonDecode(decryptedJson);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Decrypted summary is not a JSON object.');
      }

      final riskMap = <String, int>{};
      final rawRisk = decoded['risk_flag_counts'];
      if (rawRisk is Map<String, dynamic>) {
        for (final entry in rawRisk.entries) {
          if (entry.value is num) {
            riskMap[entry.key] = (entry.value as num).toInt();
          }
        }
      }

      final topEmotion = _extractTopEmotion(decoded['top_mood_paths']);
      final trend = _extractTrend(decoded['risk_flag_trend']);

      final updatedRecord = record.copyWith(
        entryCount: decoded['entry_count'] as int?,
        avgMoodScore: (decoded['avg_mood_score'] as num?)?.toDouble(),
        riskFlagCounts: riskMap,
        topEmotion: topEmotion,
        isDecrypted: true,
        riskTrend: trend,
      );

      final updated = [...state.records];
      updated[index] = updatedRecord;
      updated.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));

      state = state.copyWith(records: updated, isLoading: false, error: null);
      await _persistCache(updated);

      // TODO: Add expiry/revocation policy for locally decrypted report access.
    } catch (error) {
      state = state.copyWith(isLoading: false, error: 'Failed to decrypt report: $error');
      rethrow;
    }
  }

  Future<void> addManualPatientLabel(String reportId, String label) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return;

    final updated = state.records
        .map(
          (record) => record.reportId == reportId
              ? record.copyWith(patientLabel: trimmed)
              : record,
        )
        .toList(growable: false);

    state = state.copyWith(records: updated, error: null);
    await _persistCache(updated);
  }

  Future<void> _persistCache(List<PatientRecord> records) async {
    final encoded = jsonEncode(records.map((record) => record.toJson()).toList(growable: false));
    await _storage.settingsBox.put(_clinicianReportsCacheKey, encoded);
  }

  PatientRecord? findByReportId(String reportId) {
    for (final record in state.records) {
      if (record.reportId == reportId) {
        return record;
      }
    }
    return null;
  }

  String _defaultPatientLabel(int index) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    if (index >= 0 && index < alphabet.length) {
      return 'Patient ${alphabet[index]}';
    }
    return 'Patient ${index + 1}';
  }

  String? _extractTopEmotion(dynamic topMoodPathsRaw) {
    if (topMoodPathsRaw is List && topMoodPathsRaw.isNotEmpty) {
      final first = topMoodPathsRaw.first;
      if (first is Map<String, dynamic>) {
        final emotion = first['emotion'];
        if (emotion is String && emotion.trim().isNotEmpty) {
          return emotion;
        }
      }
    }
    return null;
  }

  List<int>? _extractTrend(dynamic trendRaw) {
    if (trendRaw is! List) return null;
    final values = <int>[];
    for (final point in trendRaw) {
      if (point is Map<String, dynamic>) {
        final count = point['flag_count'];
        if (count is num) {
          values.add(count.toInt());
        }
      }
    }
    return values.isEmpty ? null : values;
  }
}
