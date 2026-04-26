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
}
