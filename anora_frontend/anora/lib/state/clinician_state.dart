import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../services/api_endpoint_service.dart';
import '../services/clinician_crypto_service.dart';
import '../services/clinician_push_service.dart';
import '../services/storage_service.dart';

const _clinicianInboxCacheKey = 'clinician_inbox_cache';

enum ClinicianInboxItemKind { report, emergencyAlert }

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
    this.kind = ClinicianInboxItemKind.report,
    this.isUnread = false,
    this.alertPriority,
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
  final ClinicianInboxItemKind kind;
  final bool isUnread;
  final String? alertPriority;

  bool get isEmergencyAlert => kind == ClinicianInboxItemKind.emergencyAlert;

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
    ClinicianInboxItemKind? kind,
    bool? isUnread,
    String? alertPriority,
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
      kind: kind ?? this.kind,
      isUnread: isUnread ?? this.isUnread,
      alertPriority: alertPriority ?? this.alertPriority,
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
      kind: (json['kind'] as String?) == 'emergencyAlert'
          ? ClinicianInboxItemKind.emergencyAlert
          : ClinicianInboxItemKind.report,
      isUnread: json['isUnread'] == true,
      alertPriority: json['alertPriority'] as String?,
    );
  }

  factory PatientRecord.fromEmergencyAlert(Map<String, dynamic> json) {
    return PatientRecord(
      patientLabel: (json['patientLabel'] as String?) ?? 'Emergency alert',
      reportId: (json['alert_id'] as String?) ?? (json['reportId'] as String?) ?? '',
      receivedAt: DateTime.tryParse((json['created_at'] as String?) ?? (json['createdAt'] as String?) ?? '') ?? DateTime.now(),
      clinicianId: (json['clinician_id'] as String?) ?? (json['clinicianId'] as String?) ?? '',
      entryCount: null,
      avgMoodScore: null,
      riskFlagCounts: const <String, int>{'emergency': 1},
      topEmotion: 'Emergency',
      isDecrypted: false,
      encryptedKeyB64: null,
      encryptedPayload: null,
      riskTrend: null,
      kind: ClinicianInboxItemKind.emergencyAlert,
      isUnread: json['isUnread'] != false,
      alertPriority: (json['priority'] as String?) ?? 'high',
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
      'kind': kind.name,
      'isUnread': isUnread,
      'alertPriority': alertPriority,
    };
  }
}

class ClinicianReportsState {
  const ClinicianReportsState({
    this.records = const <PatientRecord>[],
    this.alerts = const <PatientRecord>[],
    this.unreadAlertIds = const <String>{},
    this.lastAlertSyncAt,
    this.isLoading = false,
    this.error,
  });

  final List<PatientRecord> records;
  final List<PatientRecord> alerts;
  final Set<String> unreadAlertIds;
  final DateTime? lastAlertSyncAt;
  final bool isLoading;
  final String? error;

  ClinicianReportsState copyWith({
    List<PatientRecord>? records,
    List<PatientRecord>? alerts,
    Set<String>? unreadAlertIds,
    DateTime? lastAlertSyncAt,
    bool? isLoading,
    String? error,
  }) {
    return ClinicianReportsState(
      records: records ?? this.records,
      alerts: alerts ?? this.alerts,
      unreadAlertIds: unreadAlertIds ?? this.unreadAlertIds,
      lastAlertSyncAt: lastAlertSyncAt ?? this.lastAlertSyncAt,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  List<PatientRecord> get inboxRecords {
    final allRecords = <PatientRecord>[...records, ...alerts];
    allRecords.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return allRecords;
  }

  int get unreadAlertCount => unreadAlertIds.length;
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
    final raw = _storage.settingsBox.get(_clinicianInboxCacheKey);
    if (raw == null) {
      state = state.copyWith(
        records: <PatientRecord>[],
        alerts: <PatientRecord>[],
        unreadAlertIds: <String>{},
        lastAlertSyncAt: null,
        isLoading: false,
        error: null,
      );
      return;
    }

    try {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is List) {
        final records = decoded
            .whereType<Map>()
            .map((map) => PatientRecord.fromJson(Map<String, dynamic>.from(map)))
            .where((record) => !record.isEmergencyAlert)
            .toList(growable: false)
          ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));

        state = state.copyWith(records: records, alerts: const <PatientRecord>[], isLoading: false, error: null);
        return;
      }

      if (decoded is! Map<String, dynamic>) {
        state = state.copyWith(error: 'Invalid local inbox cache format.');
        return;
      }

      final rawReports = decoded['records'];
      final rawAlerts = decoded['alerts'];
      final rawUnread = decoded['unreadAlertIds'];
      final rawLastSync = decoded['lastAlertSyncAt'];

      final records = _decodeRecordList(rawReports, includeAlerts: false);
      final alerts = _decodeRecordList(rawAlerts, includeAlerts: true)
          .map((record) => record.copyWith(kind: ClinicianInboxItemKind.emergencyAlert))
          .toList(growable: false)
        ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));

      final unreadAlertIds = <String>{};
      if (rawUnread is List) {
        for (final value in rawUnread) {
          if (value is String && value.trim().isNotEmpty) {
            unreadAlertIds.add(value.trim());
          }
        }
      }

      DateTime? lastAlertSyncAt;
      if (rawLastSync is String) {
        lastAlertSyncAt = DateTime.tryParse(rawLastSync);
      }

      state = state.copyWith(
        records: records,
        alerts: alerts,
        unreadAlertIds: unreadAlertIds,
        lastAlertSyncAt: lastAlertSyncAt,
        isLoading: false,
        error: null,
      );
    } catch (error) {
      state = state.copyWith(error: 'Could not parse reports cache: $error', isLoading: false);
    }
  }

  Future<void> syncEmergencyAlerts() async {
    final clinicianId = (_storage.settingsBox.get('clinician_id') as String?)?.trim();
    if (clinicianId == null || clinicianId.isEmpty) {
      return;
    }

    try {
      final alerts = await ClinicianInboxSyncService.instance.fetchEmergencyAlerts(
        clinicianId: clinicianId,
        since: state.lastAlertSyncAt,
      );

      final mergedAlerts = <PatientRecord>[];
      final existingById = <String, PatientRecord>{
        for (final alert in state.alerts) alert.reportId: alert,
      };

      final unreadIds = <String>{...state.unreadAlertIds};
      for (final snapshot in alerts) {
        final alert = PatientRecord.fromEmergencyAlert({
          'alert_id': snapshot.alertId,
          'clinician_id': snapshot.clinicianId,
          'priority': snapshot.priority,
          'created_at': snapshot.createdAt.toIso8601String(),
        });
        final existing = existingById[alert.reportId];
        final merged = alert.copyWith(
          isUnread: existing?.isUnread ?? true,
          alertPriority: existing?.alertPriority ?? alert.alertPriority,
        );
        mergedAlerts.add(merged);
        if (merged.isUnread) {
          unreadIds.add(merged.reportId);
        }
      }

      final combinedAlerts = <PatientRecord>[...state.alerts];
      for (final alert in mergedAlerts) {
        final index = combinedAlerts.indexWhere((record) => record.reportId == alert.reportId);
        if (index >= 0) {
          combinedAlerts[index] = alert;
        } else {
          combinedAlerts.add(alert);
        }
      }
      combinedAlerts.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));

      state = state.copyWith(
        alerts: combinedAlerts,
        unreadAlertIds: unreadIds,
        lastAlertSyncAt: DateTime.now().toUtc(),
        error: null,
      );
      await _persistCache();
    } catch (error) {
      state = state.copyWith(
        error: 'Could not sync alerts from ${ApiEndpointService.instance.baseUrl}: $error',
      );
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
      final response = await http.get(ApiEndpointService.instance.buildUri('/reports/$id'));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        throw Exception('Unexpected response payload.');
      }

      final sourceType = (body['source_type'] as String?) ?? 'report';

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
        kind: sourceType == 'emergency_alert'
            ? ClinicianInboxItemKind.emergencyAlert
            : ClinicianInboxItemKind.report,
        isUnread: sourceType == 'emergency_alert' ? true : false,
        alertPriority: sourceType == 'emergency_alert' ? 'high' : null,
      );

      if (sourceType == 'emergency_alert') {
        final alertIndex = state.alerts.indexWhere((record) => record.reportId == id);
        final updatedAlerts = [...state.alerts];
        if (alertIndex >= 0) {
          updatedAlerts[alertIndex] = baseRecord;
        } else {
          updatedAlerts.add(baseRecord);
        }
        updatedAlerts.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));

        final unreadIds = <String>{...state.unreadAlertIds, id};
        state = state.copyWith(alerts: updatedAlerts, unreadAlertIds: unreadIds, isLoading: false, error: null);
        await _persistCache();
        return;
      }

      final updated = [...state.records];
      if (existingIndex >= 0) {
        updated[existingIndex] = baseRecord;
      } else {
        updated.add(baseRecord);
      }
      updated.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));

      state = state.copyWith(records: updated, isLoading: false, error: null);
      await _persistCache();
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
      await _persistCache();

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
    await _persistCache();
  }

  Future<void> markAlertRead(String alertId) async {
    if (alertId.trim().isEmpty) return;

    final updatedAlerts = state.alerts
        .map(
          (record) => record.reportId == alertId
              ? record.copyWith(isUnread: false)
              : record,
        )
        .toList(growable: false);

    final unreadIds = <String>{...state.unreadAlertIds}..remove(alertId);
    state = state.copyWith(alerts: updatedAlerts, unreadAlertIds: unreadIds, error: null);
    await _persistCache();
  }

  Future<void> _persistCache() async {
    final encoded = jsonEncode(
      {
        'records': state.records.map((record) => record.toJson()).toList(growable: false),
        'alerts': state.alerts.map((record) => record.toJson()).toList(growable: false),
        'unreadAlertIds': state.unreadAlertIds.toList(growable: false),
        'lastAlertSyncAt': state.lastAlertSyncAt?.toIso8601String(),
      },
    );
    await _storage.settingsBox.put(_clinicianInboxCacheKey, encoded);
  }

  PatientRecord? findByReportId(String reportId) {
    for (final record in state.records) {
      if (record.reportId == reportId) {
        return record;
      }
    }
    for (final alert in state.alerts) {
      if (alert.reportId == reportId) {
        return alert;
      }
    }
    return null;
  }

  List<PatientRecord> _decodeRecordList(dynamic raw, {required bool includeAlerts}) {
    if (raw is! List) return <PatientRecord>[];

    final records = <PatientRecord>[];
    for (final value in raw) {
      if (value is! Map) continue;
      final record = PatientRecord.fromJson(Map<String, dynamic>.from(value));
      if (includeAlerts || !record.isEmergencyAlert) {
        records.add(record);
      }
    }
    records.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return records;
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
