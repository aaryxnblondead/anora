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
