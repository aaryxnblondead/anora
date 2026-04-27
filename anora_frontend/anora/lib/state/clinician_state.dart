import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_endpoint_service.dart';
import '../services/clinician_crypto_service.dart';
import '../services/clinician_push_service.dart';
import '../services/storage_service.dart';

const _clinicianInboxCacheKey = 'clinician_inbox_cache';
const _decryptedAccessTimesKey = 'clinician_decrypted_access_times';
const _decryptedAccessTtl = Duration(hours: 24);

enum ClinicianInboxItemKind { report, emergencyAlert, moodUpdate }

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
    this.patientDeviceId,
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
  final String? patientDeviceId;
  final ClinicianInboxItemKind kind;
  final bool isUnread;
  final String? alertPriority;

  bool get isEmergencyAlert => kind == ClinicianInboxItemKind.emergencyAlert;
  bool get isMoodUpdate => kind == ClinicianInboxItemKind.moodUpdate;
  bool get isReport => kind == ClinicianInboxItemKind.report;

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
    String? patientDeviceId,
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
      patientDeviceId: patientDeviceId ?? this.patientDeviceId,
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
      patientDeviceId: json['patientDeviceId'] as String?,
      kind: switch (json['kind'] as String?) {
        'emergencyAlert' => ClinicianInboxItemKind.emergencyAlert,
        'moodUpdate' => ClinicianInboxItemKind.moodUpdate,
        _ => ClinicianInboxItemKind.report,
      },
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

  factory PatientRecord.fromMoodSnapshot({
    required ClinicianMoodSnapshot snapshot,
    required String patientLabel,
  }) {
    final riskFlagCounts = <String, int>{};
    for (final flag in snapshot.riskFlags) {
      if (flag.trim().isEmpty) continue;
      riskFlagCounts.update(flag, (value) => value + 1, ifAbsent: () => 1);
    }

    final topEmotion =
        snapshot.moodLabels.isNotEmpty ? snapshot.moodLabels.last : null;

    return PatientRecord(
      patientLabel: patientLabel,
      reportId: snapshot.eventId,
      receivedAt: snapshot.eventTimestamp ?? snapshot.createdAt,
      clinicianId: snapshot.clinicianId,
      entryCount: 1,
      avgMoodScore: snapshot.moodScore,
      riskFlagCounts: riskFlagCounts,
      topEmotion: topEmotion,
      isDecrypted: true,
      encryptedKeyB64: null,
      encryptedPayload: null,
      riskTrend: null,
      patientDeviceId: snapshot.patientDeviceId,
      kind: ClinicianInboxItemKind.moodUpdate,
      isUnread: false,
      alertPriority: null,
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
      'patientDeviceId': patientDeviceId,
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
    this.lastReportSyncAt,
    this.isLoading = false,
    this.error,
  });

  final List<PatientRecord> records;
  final List<PatientRecord> alerts;
  final Set<String> unreadAlertIds;
  final DateTime? lastAlertSyncAt;
  final DateTime? lastReportSyncAt;
  final bool isLoading;
  final String? error;

  ClinicianReportsState copyWith({
    List<PatientRecord>? records,
    List<PatientRecord>? alerts,
    Set<String>? unreadAlertIds,
    DateTime? lastAlertSyncAt,
    DateTime? lastReportSyncAt,
    bool? isLoading,
    String? error,
  }) {
    return ClinicianReportsState(
      records: records ?? this.records,
      alerts: alerts ?? this.alerts,
      unreadAlertIds: unreadAlertIds ?? this.unreadAlertIds,
      lastAlertSyncAt: lastAlertSyncAt ?? this.lastAlertSyncAt,
      lastReportSyncAt: lastReportSyncAt ?? this.lastReportSyncAt,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  List<PatientRecord> get inboxRecords {
    final allRecords = <PatientRecord>[...records, ...alerts];
    allRecords.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return allRecords;
  }

  int get unreadAlertCount => alerts.where((alert) => alert.isUnread).length;
}

final clinicianReportsProvider =
    StateNotifierProvider<ClinicianReportsNotifier, ClinicianReportsState>(
  (ref) => ClinicianReportsNotifier(StorageService.instance),
);

class ClinicianReportsNotifier extends StateNotifier<ClinicianReportsState> {
  ClinicianReportsNotifier(this._storage) : super(const ClinicianReportsState()) {
    loadFromLocalCache();
    Future.microtask(_expireDecryptedRecordsIfNeeded);
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
        lastReportSyncAt: null,
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
      final rawLastReportSync = decoded['lastReportSyncAt'];

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

      DateTime? lastReportSyncAt;
      if (rawLastReportSync is String) {
        lastReportSyncAt = DateTime.tryParse(rawLastReportSync);
      }

      state = state.copyWith(
        records: records,
        alerts: alerts,
        unreadAlertIds: unreadAlertIds,
        lastAlertSyncAt: lastAlertSyncAt,
        lastReportSyncAt: lastReportSyncAt,
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

  Future<void> syncLatestReports() async {
    final clinicianId = (_storage.settingsBox.get('clinician_id') as String?)?.trim();
    if (clinicianId == null || clinicianId.isEmpty) {
      return;
    }

    try {
      final snapshots = await ClinicianInboxSyncService.instance.fetchLatestReports(
        clinicianId: clinicianId,
        since: state.lastReportSyncAt,
        limit: 50,
      );

      if (snapshots.isEmpty) {
        state = state.copyWith(lastReportSyncAt: DateTime.now().toUtc(), error: null);
        await _persistCache();
        return;
      }

      final existingById = <String, PatientRecord>{
        for (final record in state.records.where((record) => record.isReport))
          record.reportId: record,
      };

      final preservedNonReportRecords = state.records
          .where((record) => !record.isReport)
          .toList(growable: true);

      for (final snapshot in snapshots) {
        final lockedBox = snapshot.lockedBox;
        final encryptedKeyB64 = lockedBox['encrypted_key'];
        final encryptedPayloadRaw = lockedBox['encrypted_payload'];
        if (encryptedKeyB64 is! String || encryptedPayloadRaw is! Map<String, dynamic>) {
          continue;
        }

        final encryptedPayload = <String, String>{};
        for (final entry in encryptedPayloadRaw.entries) {
          encryptedPayload[entry.key] = entry.value.toString();
        }

        final baseRecord = PatientRecord(
          patientLabel: _defaultPatientLabel(preservedNonReportRecords.length),
          reportId: snapshot.reportId,
          receivedAt: snapshot.createdAt,
          clinicianId: snapshot.clinicianId,
          entryCount: null,
          avgMoodScore: null,
          riskFlagCounts: null,
          topEmotion: null,
          isDecrypted: false,
          encryptedKeyB64: encryptedKeyB64,
          encryptedPayload: encryptedPayload,
          riskTrend: null,
          kind: ClinicianInboxItemKind.report,
          isUnread: false,
          alertPriority: null,
        );

        final existing = existingById[snapshot.reportId];
        final merged = existing == null
            ? baseRecord
            : baseRecord.copyWith(
                patientLabel: existing.patientLabel,
                isDecrypted: existing.isDecrypted,
                entryCount: existing.entryCount,
                avgMoodScore: existing.avgMoodScore,
                riskFlagCounts: existing.riskFlagCounts,
                topEmotion: existing.topEmotion,
                riskTrend: existing.riskTrend,
              );

        existingById[snapshot.reportId] = merged;
      }

      preservedNonReportRecords.addAll(existingById.values);
      preservedNonReportRecords.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));

      state = state.copyWith(
        records: preservedNonReportRecords,
        lastReportSyncAt: DateTime.now().toUtc(),
        error: null,
      );
      await _persistCache();
    } catch (error) {
      state = state.copyWith(
        error: 'Could not sync reports from ${ApiEndpointService.instance.baseUrl}: $error',
      );
    }
  }

  Future<void> syncLatestMoodUpdates() async {
    final clinicianId = (_storage.settingsBox.get('clinician_id') as String?)?.trim();
    if (clinicianId == null || clinicianId.isEmpty) {
      return;
    }

    try {
      final updates = await ClinicianInboxSyncService.instance.fetchLatestMoodUpdates(
        clinicianId: clinicianId,
        limit: 100,
      );

      final retainedRecords = state.records
          .where((record) => !record.isMoodUpdate)
          .toList(growable: true);

      final labelsByDeviceId = <String, String>{};
      for (final record in state.records) {
        final deviceId = record.patientDeviceId;
        if (deviceId == null || deviceId.trim().isEmpty) continue;
        labelsByDeviceId[deviceId] = record.patientLabel;
      }

      final moodRecords = <PatientRecord>[];
      for (final snapshot in updates) {
        final patientLabel =
            labelsByDeviceId[snapshot.patientDeviceId] ?? _labelFromDeviceId(snapshot.patientDeviceId);
        final record = PatientRecord.fromMoodSnapshot(
          snapshot: snapshot,
          patientLabel: patientLabel,
        );
        moodRecords.add(record);
      }

      retainedRecords.addAll(moodRecords);
      retainedRecords.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));

      state = state.copyWith(records: retainedRecords, error: null);
      await _persistCache();
    } catch (error) {
      state = state.copyWith(
        error: 'Could not sync latest moods from ${ApiEndpointService.instance.baseUrl}: $error',
      );
    }
  }

  Future<void> fetchReport(String reportId) async {
    final id = reportId.trim();
    if (id.isEmpty) {
      state = state.copyWith(error: 'Report ID is required.');
      return;
    }

    final clinicianJwt = (_storage.settingsBox.get('clinician_jwt') as String?)?.trim();
    if (clinicianJwt == null || clinicianJwt.isEmpty) {
      state = state.copyWith(error: 'Clinician session token is missing. Please sign in again.');
      return;
    }

    final registeredClinicianId =
        (_storage.settingsBox.get('clinician_id') as String?)?.trim();
    if (registeredClinicianId == null || registeredClinicianId.isEmpty) {
      state = state.copyWith(error: 'Clinician ID is missing on this device.');
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await ApiEndpointService.instance.get(
        ApiEndpointService.instance.buildUri('/reports/$id'),
        headers: <String, String>{
          'Authorization': 'Bearer $clinicianJwt',
        },
      );
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

      final clinicianId = ((body['clinician_id'] as String?) ?? '').trim();
      if (clinicianId.isEmpty || clinicianId != registeredClinicianId) {
        throw Exception('Report clinician ID does not match the signed-in clinician.');
      }
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

  Future<void> decryptRecord(String reportId, {required bool consentGranted}) async {
    if (!consentGranted) {
      state = state.copyWith(error: 'Patient consent is required before decrypting a report.');
      throw Exception('Patient consent is required before decrypting a report.');
    }

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
      final accessTimes = _loadDecryptedAccessTimes();
      accessTimes[reportId] = DateTime.now().toUtc();
      await _saveDecryptedAccessTimes(accessTimes);
      await _persistCache();
    } catch (error) {
      state = state.copyWith(isLoading: false, error: 'Failed to decrypt report: $error');
      rethrow;
    }
  }

  Future<void> revokeDecryptedRecordAccess(String reportId) async {
    final trimmedId = reportId.trim();
    if (trimmedId.isEmpty) return;

    final updatedRecords = state.records
        .map((record) => record.reportId == trimmedId ? _lockRecord(record) : record)
        .toList(growable: false);

    final accessTimes = _loadDecryptedAccessTimes();
    accessTimes.remove(trimmedId);

    state = state.copyWith(records: updatedRecords, error: null);
    await _saveDecryptedAccessTimes(accessTimes);
    await _persistCache();
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
        'lastReportSyncAt': state.lastReportSyncAt?.toIso8601String(),
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

  String _labelFromDeviceId(String patientDeviceId) {
    final safe = patientDeviceId.trim();
    if (safe.isEmpty) return 'Patient';
    final preview = safe.length <= 6 ? safe : safe.substring(0, 6);
    return 'Patient $preview';
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

  Future<void> _expireDecryptedRecordsIfNeeded() async {
    final now = DateTime.now().toUtc();
    final accessTimes = _loadDecryptedAccessTimes();
    var recordsChanged = false;
    var timesChanged = false;

    final updatedRecords = state.records.map((record) {
      if (!record.isDecrypted) {
        return record;
      }

      final decryptedAt = accessTimes[record.reportId] ?? record.receivedAt.toUtc();
      if (!accessTimes.containsKey(record.reportId)) {
        accessTimes[record.reportId] = decryptedAt;
        timesChanged = true;
      }

      if (now.difference(decryptedAt) <= _decryptedAccessTtl) {
        return record;
      }

      accessTimes.remove(record.reportId);
      timesChanged = true;
      recordsChanged = true;
      return _lockRecord(record);
    }).toList(growable: false);

    if (recordsChanged) {
      state = state.copyWith(records: updatedRecords, error: null);
      await _persistCache();
    }

    if (timesChanged) {
      await _saveDecryptedAccessTimes(accessTimes);
    }
  }

  PatientRecord _lockRecord(PatientRecord record) {
    return record.copyWith(
      isDecrypted: false,
      entryCount: null,
      avgMoodScore: null,
      riskFlagCounts: null,
      topEmotion: null,
      riskTrend: null,
    );
  }

  Map<String, DateTime> _loadDecryptedAccessTimes() {
    final raw = _storage.settingsBox.get(_decryptedAccessTimesKey);
    if (raw is! Map) {
      return <String, DateTime>{};
    }

    final decoded = <String, DateTime>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || value is! String) continue;
      final parsed = DateTime.tryParse(value);
      if (parsed == null) continue;
      decoded[key] = parsed.toUtc();
    }
    return decoded;
  }

  Future<void> _saveDecryptedAccessTimes(Map<String, DateTime> value) async {
    final encoded = <String, String>{
      for (final entry in value.entries) entry.key: entry.value.toUtc().toIso8601String(),
    };
    await _storage.settingsBox.put(_decryptedAccessTimesKey, encoded);
  }
}
