import 'dart:convert';

import '../models/journal_entry.dart';
import 'api_endpoint_service.dart';
import 'crypto_service.dart';
import 'storage_service.dart';

class ReportUploadException implements Exception {
  ReportUploadException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'ReportUploadException(statusCode: $statusCode, body: $body)';
}

class ReportService {
  ReportService._();

  static final ReportService instance = ReportService._();

  Future<Map<String, dynamic>> generateSummary({
    required DateTime from,
    required DateTime to,
  }) async {
    if (to.isBefore(from)) {
      throw ArgumentError('to must be on or after from');
    }

    final fromUtc = from.toUtc();
    final toUtc = to.toUtc();
    final entries = StorageService.instance.journalBox.values
        .where(
          (entry) =>
              !entry.timestamp.toUtc().isBefore(fromUtc) &&
              !entry.timestamp.toUtc().isAfter(toUtc),
        )
        .toList(growable: false);

    final entryCount = entries.length;
    final avgMood = entryCount == 0
        ? 0.0
        : double.parse(
            (entries.map((entry) => entry.moodScore).reduce((a, b) => a + b) / entryCount)
                .toStringAsFixed(2),
          );

    final moodDistribution = <String, int>{
      'bright': 0,
      'good': 0,
      'steady': 0,
      'low': 0,
      'rough': 0,
    };

    final riskFlagCounts = <String, int>{
      'Anxiety': 0,
      'Depression': 0,
      'Self-harm': 0,
      'Mania': 0,
    };

    final topLevelMoodPathCounts = <String, int>{};

    for (final entry in entries) {
      final score = entry.moodScore;
      if (score >= 0.78) {
        moodDistribution['bright'] = moodDistribution['bright']! + 1;
      } else if (score >= 0.62) {
        moodDistribution['good'] = moodDistribution['good']! + 1;
      } else if (score >= 0.46) {
        moodDistribution['steady'] = moodDistribution['steady']! + 1;
      } else if (score >= 0.30) {
        moodDistribution['low'] = moodDistribution['low']! + 1;
      } else {
        moodDistribution['rough'] = moodDistribution['rough']! + 1;
      }

      for (final flag in entry.riskFlags) {
        if (riskFlagCounts.containsKey(flag)) {
          riskFlagCounts[flag] = riskFlagCounts[flag]! + 1;
        }
      }

      if (entry.moodPath.isNotEmpty && entry.moodPath.first.trim().isNotEmpty) {
        final emotion = entry.moodPath.first.trim();
        topLevelMoodPathCounts[emotion] = (topLevelMoodPathCounts[emotion] ?? 0) + 1;
      }
    }

    final riskFlagTrend = _buildRiskFlagTrend(entries, fromUtc, toUtc);

    final topMoodPaths = topLevelMoodPathCounts.entries.toList(growable: false)
      ..sort((a, b) => b.value.compareTo(a.value));

    final topMoodPathSummary = topMoodPaths
        .take(3)
        .map(
          (entry) => <String, dynamic>{
            'emotion': entry.key,
            'count': entry.value,
          },
        )
        .toList(growable: false);

    return <String, dynamic>{
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'period': <String, String>{
        'from': fromUtc.toIso8601String(),
        'to': toUtc.toIso8601String(),
      },
      'entry_count': entryCount,
      'avg_mood_score': avgMood,
      'mood_distribution': moodDistribution,
      'risk_flag_counts': riskFlagCounts,
      'risk_flag_trend': riskFlagTrend,
      'top_mood_paths': topMoodPathSummary,
      'disclaimer': 'AI-assisted summary only. Not a clinical diagnosis.',
    };
  }

  Map<String, dynamic> buildLockedBox({
    required Map<String, dynamic> summary,
    required String clinicianPublicKeyPem,
  }) {
    final summaryJson = jsonEncode(summary);
    final aesKey = CryptoService.instance.generateAesKey();
    final cipherBundle = CryptoService.instance.encryptAes(aesKey, summaryJson);
    final encryptedKey = CryptoService.instance.encryptRsa(clinicianPublicKeyPem, aesKey);

    return <String, dynamic>{
      'schema_version': '1.0',
      'encrypted_payload': cipherBundle,
      'encrypted_key': encryptedKey,
      'key_algorithm': 'RSA-OAEP-SHA256',
      'payload_algorithm': 'AES-256-GCM',
    };
  }

  Future<String> uploadLockedBox({
    required Map<String, dynamic> lockedBox,
    required String clinicianId,
  }) async {
    final normalizedClinicianId = clinicianId.trim();
    if (normalizedClinicianId.isEmpty) {
      throw ArgumentError('clinicianId must be non-empty');
    }

    if (!_isLikelyClinicianId(normalizedClinicianId)) {
      throw ArgumentError('clinicianId format is invalid');
    }

    final registeredClinicianId =
        (StorageService.instance.settingsBox.get('clinician_id') as String?)
            ?.trim();
    if (registeredClinicianId != null &&
        registeredClinicianId.isNotEmpty &&
        registeredClinicianId != normalizedClinicianId) {
      throw StateError(
        'clinicianId does not match the registered clinician on this device.',
      );
    }

    final uri = ApiEndpointService.instance.buildUri('/reports');
    final response = await ApiEndpointService.instance.post(
      uri,
      headers: const <String, String>{
        'Content-Type': 'application/json',
      },
      body: jsonEncode(
        <String, dynamic>{
          'clinician_id': normalizedClinicianId,
          'locked_box': lockedBox,
        },
      ),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ReportUploadException(response.statusCode, response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw ReportUploadException(response.statusCode, response.body);
    }

    final reportId = decoded['report_id'];
    if (reportId is! String || reportId.isEmpty) {
      throw ReportUploadException(response.statusCode, response.body);
    }

    return reportId;
  }

  bool _isLikelyClinicianId(String value) {
    final clinicianIdRegex = RegExp(r'^[a-zA-Z0-9_-]{6,64}$');
    return clinicianIdRegex.hasMatch(value);
  }

  /// Syncs ONLY the mood and risk indicators of a single entry. 
  /// The actual journal text is strictly omitted for patient privacy.
  Future<void> syncMoodTelemetry({
    required JournalEntry entry,
    required String clinicianId,
    required String clinicianPublicKeyPem,
  }) async {
    // 1. Create the stripped-down payload (NO TEXT INCLUDED)
    final telemetryPayload = <String, dynamic>{
      'type': 'live_telemetry',
      'entry_id': entry.id,
      'timestamp': entry.timestamp.toUtc().toIso8601String(),
      'mood_score': entry.moodScore,
      'mood_path': entry.moodPath,
      'risk_flags': entry.riskFlags,
    };

    // 2. Encrypt it using your existing secure RSA/AES pipeline
    final lockedBox = buildLockedBox(
      summary: telemetryPayload, 
      clinicianPublicKeyPem: clinicianPublicKeyPem,
    );

    // 3. Silently upload to the clinician's dashboard
    await uploadLockedBox(
      lockedBox: lockedBox,
      clinicianId: clinicianId,
    );
  }

  List<Map<String, dynamic>> _buildRiskFlagTrend(
    List<JournalEntry> entries,
    DateTime fromUtc,
    DateTime toUtc,
  ) {
    final startDay = DateTime.utc(fromUtc.year, fromUtc.month, fromUtc.day);
    final endDay = DateTime.utc(toUtc.year, toUtc.month, toUtc.day);

    final dailyCounts = <String, int>{};
    var cursor = startDay;
    while (!cursor.isAfter(endDay)) {
      dailyCounts[_dateKey(cursor)] = 0;
      cursor = cursor.add(const Duration(days: 1));
    }

    for (final entry in entries) {
      final entryUtc = entry.timestamp.toUtc();
      final dayKey = _dateKey(DateTime.utc(entryUtc.year, entryUtc.month, entryUtc.day));
      final current = dailyCounts[dayKey] ?? 0;
      dailyCounts[dayKey] = current + entry.riskFlags.length;
    }

    final sortedKeys = dailyCounts.keys.toList(growable: false)..sort();
    return sortedKeys
        .map(
          (key) => <String, dynamic>{
            'date': key,
            'flag_count': dailyCounts[key] ?? 0,
          },
        )
        .toList(growable: false);
  }

  String _dateKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Future<String> generateInviteCode(String clinicianId) async {
    final normalizedClinicianId = clinicianId.trim();
    if (normalizedClinicianId.isEmpty) {
      throw ArgumentError('clinicianId must be non-empty');
    }

    final uri = ApiEndpointService.instance.buildUri('/clinicians/generate-code');
    final response = await ApiEndpointService.instance.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'clinician_id': normalizedClinicianId}),
    );

    // Legacy backend compatibility: older deployments do not implement
    // /clinicians/generate-code and still rely on sharing clinician_id directly.
    if (response.statusCode == 404) {
      return normalizedClinicianId;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ReportUploadException(response.statusCode, response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw ReportUploadException(response.statusCode, 'Invalid response format');
    }

    final code = decoded['invite_code'];
    if (code is! String || code.isEmpty) {
      throw ReportUploadException(response.statusCode, 'Invite code not found in response');
    }

    return code;
  }

  Future<List<Map<String, dynamic>>> fetchFeedForClinician(
    String clinicianId, {
    String? since,
    int limit = 100,
  }) async {
    if (clinicianId.trim().isEmpty) {
      throw ArgumentError('clinicianId must be non-empty');
    }

    final queryParameters = <String, String>{
      'limit': limit.toString(),
    };
    if (since != null && since.isNotEmpty) {
      queryParameters['since'] = since;
    }

    final uri = ApiEndpointService.instance.buildUri(
      '/clinician/$clinicianId/feed',
      queryParameters: queryParameters,
    );

    final response = await ApiEndpointService.instance.get(uri);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ReportUploadException(response.statusCode, response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['feed'] is! List) {
      throw ReportUploadException(response.statusCode, 'Invalid feed format');
    }

    return List<Map<String, dynamic>>.from(decoded['feed']);
  }
}