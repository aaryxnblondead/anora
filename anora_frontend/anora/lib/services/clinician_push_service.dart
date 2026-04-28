import 'dart:convert';

import 'api_endpoint_service.dart';

class ClinicianInboxAlertSnapshot {
  const ClinicianInboxAlertSnapshot({
    required this.alertId,
    required this.clinicianId,
    required this.priority,
    required this.createdAt,
  });

  final String alertId;
  final String clinicianId;
  final String priority;
  final DateTime createdAt;

  factory ClinicianInboxAlertSnapshot.fromJson(Map<String, dynamic> json) {
    return ClinicianInboxAlertSnapshot(
      alertId: (json['alert_id'] as String?) ?? '',
      clinicianId: (json['clinician_id'] as String?) ?? '',
      priority: (json['priority'] as String?) ?? 'high',
      createdAt: DateTime.tryParse((json['created_at'] as String?) ?? '') ?? DateTime.now(),
    );
  }
}

class ClinicianMoodSnapshot {
  const ClinicianMoodSnapshot({
    required this.eventId,
    required this.patientDeviceId,
    required this.clinicianId,
    required this.moodScore,
    required this.moodLabels,
    required this.riskFlags,
    required this.createdAt,
    this.eventTimestamp,
  });

  final String eventId;
  final String patientDeviceId;
  final String clinicianId;
  final double? moodScore;
  final List<String> moodLabels;
  final List<String> riskFlags;
  final DateTime createdAt;
  final DateTime? eventTimestamp;

  factory ClinicianMoodSnapshot.fromJson(Map<String, dynamic> json) {
    final rawLabels = json['mood_labels'];
    final labels = <String>[];
    if (rawLabels is List) {
      for (final value in rawLabels) {
        if (value is String && value.trim().isNotEmpty) {
          labels.add(value.trim());
        }
      }
    }

    final rawFlags = json['risk_flags'];
    final flags = <String>[];
    if (rawFlags is List) {
      for (final value in rawFlags) {
        if (value is String && value.trim().isNotEmpty) {
          flags.add(value.trim());
        }
      }
    }

    return ClinicianMoodSnapshot(
      eventId: (json['event_id'] as String?) ?? '',
      patientDeviceId: (json['patient_device_id'] as String?) ?? '',
      clinicianId: (json['clinician_id'] as String?) ?? '',
      moodScore: (json['mood_score'] as num?)?.toDouble(),
      moodLabels: labels,
      riskFlags: flags,
      createdAt: DateTime.tryParse((json['created_at'] as String?) ?? '') ?? DateTime.now(),
      eventTimestamp: DateTime.tryParse((json['event_timestamp'] as String?) ?? ''),
    );
  }
}

class ClinicianInboxSyncService {
  ClinicianInboxSyncService._();

  static final ClinicianInboxSyncService instance = ClinicianInboxSyncService._();

  Future<List<ClinicianInboxAlertSnapshot>> fetchEmergencyAlerts({
    required String clinicianId,
    DateTime? since,
  }) async {
    final uri = ApiEndpointService.instance.buildUri(
      '/alerts/emergency/$clinicianId',
      queryParameters: <String, String>{
        if (since != null) 'since': since.toUtc().toIso8601String(),
        'limit': '100',
      },
    );

    final response = await ApiEndpointService.instance.get(uri);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected alert response payload.');
    }

    final rawAlerts = decoded['alerts'];
    if (rawAlerts is! List) {
      return const <ClinicianInboxAlertSnapshot>[];
    }

    return rawAlerts
        .whereType<Map>()
        .map((map) => ClinicianInboxAlertSnapshot.fromJson(Map<String, dynamic>.from(map)))
        .toList(growable: false);
  }

  Future<List<LinkedPatientEntry>> fetchLinkedPatients({
    required String clinicianId,
  }) async {
    // Uses GET /patients/linked/{clinician_id}
    // Does NOT use ReportUploadException — this is a read, not an upload
    final uri = ApiEndpointService.instance
        .buildUri('/patients/linked/$clinicianId');
    final response = await ApiEndpointService.instance.get(uri);
    if (response.statusCode != 200) {
      // Throw a plain Exception, never ReportUploadException for GETs
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected linked patients response shape.');
    }
    final rawList = decoded['patients'];
    if (rawList is! List) return const [];
    return rawList
        .whereType<Map>()
        .map((m) => LinkedPatientEntry.fromJson(
              Map<String, dynamic>.from(m)))
        .where((e) => e.patientDeviceId.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<ClinicianReportSnapshot>> fetchLatestReports({
    required String clinicianId,
    DateTime? since,
    int limit = 50,
  }) async {
    // Uses GET /reports/clinician/{clinician_id}
    // Does NOT use ReportUploadException — this is a read, not an upload
    final uri = ApiEndpointService.instance.buildUri(
      '/reports/clinician/$clinicianId',
      queryParameters: <String, String>{
        if (since != null) 'since': since.toUtc().toIso8601String(),
        'limit': '$limit',
      },
    );
    final response = await ApiEndpointService.instance.get(uri);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected report list response shape.');
    }
    final rawList = decoded['reports'];
    if (rawList is! List) return const [];
    return rawList
        .whereType<Map>()
        .map((m) => ClinicianReportSnapshot.fromJson(
              Map<String, dynamic>.from(m)))
        .where((s) => s.reportId.isNotEmpty)
        .toList(growable: false);
  }
}

extension ClinicianInboxSyncServiceReports on ClinicianInboxSyncService {}

extension ClinicianInboxSyncServiceMood on ClinicianInboxSyncService {
  Future<List<LinkedPatientEntry>> fetchLinkedPatients({
    required String clinicianId,
  }) async {
    final uri = ApiEndpointService.instance
        .buildUri('/patients/linked/$clinicianId');
    final response = await ApiEndpointService.instance.get(uri);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected linked patients response shape.');
    }
    final rawList = decoded['patients'];
    if (rawList is! List) return const [];
    return rawList
        .whereType<Map>()
        .map((m) => LinkedPatientEntry.fromJson(
              Map<String, dynamic>.from(m),
            ))
        .where((e) => e.patientDeviceId.isNotEmpty)
        .toList(growable: false);
  }
  Future<List<ClinicianMoodSnapshot>> fetchLatestMoodUpdates({
    required String clinicianId,
    int limit = 100,
  }) async {
    final uri = ApiEndpointService.instance.buildUri(
      '/telemetry/mood-events/latest/$clinicianId',
      queryParameters: <String, String>{
        'limit': '$limit',
      },
    );

    final response = await ApiEndpointService.instance.get(uri);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected mood response payload.');
    }

    final rawEvents = decoded['events'];
    if (rawEvents is! List) {
      return const <ClinicianMoodSnapshot>[];
    }

    return rawEvents
        .whereType<Map>()
        .map((map) => ClinicianMoodSnapshot.fromJson(Map<String, dynamic>.from(map)))
        .where((snapshot) =>
            snapshot.eventId.isNotEmpty &&
            snapshot.patientDeviceId.isNotEmpty &&
            snapshot.clinicianId.isNotEmpty)
        .toList(growable: false);
  }
}

// ── New model ─────────────────────────────────────────────

class LinkedPatientMoodSnapshot {
  const LinkedPatientMoodSnapshot({
    required this.moodScore,
    required this.moodLabels,
    required this.riskFlags,
    required this.lastMoodAt,
  });

  final double moodScore;
  final List<String> moodLabels;
  final List<String> riskFlags;
  final DateTime lastMoodAt;

  bool get hasRiskFlags => riskFlags.isNotEmpty;

  String get moodDescriptor {
    if (moodScore >= 0.78) return 'Bright';
    if (moodScore >= 0.62) return 'Good';
    if (moodScore >= 0.46) return 'Steady';
    if (moodScore >= 0.30) return 'Low';
    return 'Rough';
  }

  factory LinkedPatientMoodSnapshot.fromJson(Map<String, dynamic> json) {
    final rawLabels = json['mood_labels'];
    final labels = rawLabels is List
        ? rawLabels.whereType<String>().toList(growable: false)
        : <String>[];
    final rawFlags = json['risk_flags'];
    final flags = rawFlags is List
        ? rawFlags.whereType<String>().toList(growable: false)
        : <String>[];
    final rawAt = json['last_mood_at'] as String? ?? '';
    return LinkedPatientMoodSnapshot(
      moodScore: (json['mood_score'] as num?)?.toDouble() ?? 0.5,
      moodLabels: labels,
      riskFlags: flags,
      lastMoodAt: DateTime.tryParse(rawAt) ?? DateTime.now(),
    );
  }
}

class LinkedPatientEntry {
  const LinkedPatientEntry({
    required this.patientDeviceId,
    required this.patientLabel,
    required this.linkedAt,
    required this.moodHistory,
    this.latestMood,
  });

  final String patientDeviceId;
  final String patientLabel;
  final DateTime linkedAt;
  final List<double> moodHistory;
  final LinkedPatientMoodSnapshot? latestMood;

  bool get hasMoodData => latestMood != null;

  static String labelFromDeviceId(String id) {
    final safe = id.trim().toUpperCase();
    final preview = safe.length < 6 ? safe : safe.substring(0, 6);
    return 'Patient $preview';
  }

  LinkedPatientEntry copyWith({
    String? patientLabel,
    List<double>? moodHistory,
    LinkedPatientMoodSnapshot? latestMood,
  }) {
    return LinkedPatientEntry(
      patientDeviceId: patientDeviceId,
      patientLabel: patientLabel ?? this.patientLabel,
      linkedAt: linkedAt,
      moodHistory: moodHistory ?? this.moodHistory,
      latestMood: latestMood ?? this.latestMood,
    );
  }

  factory LinkedPatientEntry.fromJson(Map<String, dynamic> json) {
    final rawLinkedAt = json['linked_at'] as String? ?? '';
    final rawMood = json['latest_mood'];
    LinkedPatientMoodSnapshot? mood;
    if (rawMood is Map<String, dynamic>) {
      mood = LinkedPatientMoodSnapshot.fromJson(rawMood);
    }
    final deviceId = (json['patient_device_id'] as String?) ?? '';
    final rawHistory = json['mood_history'];
    final history = <double>[];
    if (rawHistory is List) {
      for (final value in rawHistory) {
        if (value is num) {
          history.add(value.toDouble());
        }
      }
    }
    return LinkedPatientEntry(
      patientDeviceId: deviceId,
      patientLabel: LinkedPatientEntry.labelFromDeviceId(deviceId),
      linkedAt: DateTime.tryParse(rawLinkedAt) ?? DateTime.now(),
      moodHistory: history,
      latestMood: mood,
    );
  }
}

// ── New report snapshot model ──────────────────────────────

class ClinicianReportSnapshot {
  const ClinicianReportSnapshot({
    required this.reportId,
    required this.clinicianId,
    required this.lockedBox,
    required this.createdAt,
  });

  final String reportId;
  final String clinicianId;
  final Map<String, dynamic> lockedBox;
  final DateTime createdAt;

  factory ClinicianReportSnapshot.fromJson(Map<String, dynamic> json) {
    return ClinicianReportSnapshot(
      reportId: (json['report_id'] as String?) ?? '',
      clinicianId: (json['clinician_id'] as String?) ?? '',
      lockedBox: (json['locked_box'] as Map<String, dynamic>?) ?? {},
      createdAt: DateTime.tryParse(
              (json['created_at'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}
