import 'dart:convert';
import 'dart:math';

import '../models/journal_entry.dart';
import 'api_endpoint_service.dart';
import 'report_service.dart';
import 'storage_service.dart';

class SecureLinkService {
  SecureLinkService._();

  static final SecureLinkService instance = SecureLinkService._();

  static const _linkedClinicianIdKey = 'linked_clinician_id';
  static const _linkedClinicianPublicKeyKey = 'linked_clinician_public_key_pem';
  static const _patientDeviceIdKey = 'patient_device_id';
  static const _clinicianJwtKey = 'clinician_jwt';
  static const _clinicianOptInSettingKey = 'setting_clinician_opt_in';

  String? _lastLinkError;

  String? get linkedClinicianId {
    final value = StorageService.instance.settingsBox.get(_linkedClinicianIdKey);
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  bool get isLinked => linkedClinicianId != null;

  String? get linkedClinicianPublicKeyPem => _linkedClinicianPublicKey();
  String? get lastLinkError => _lastLinkError;

  Future<bool> linkClinicianWithCode(String inviteCode) async {
    final trimmedInput = inviteCode.trim();
    final normalizedInviteCode = trimmedInput.toUpperCase();
    if (normalizedInviteCode.isEmpty) {
      _lastLinkError = 'Invite code is required.';
      return false;
    }

    try {
      final patientDeviceId = await _getOrCreatePatientDeviceId();
      final uri = ApiEndpointService.instance.buildUri('/patients/link-with-code');
      final response = await ApiEndpointService.instance.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(
          {
            'patient_device_id': patientDeviceId,
            'invite_code': normalizedInviteCode,
          },
        ),
      );

      // Legacy backend compatibility: retry with /clinicians/link when the
      // invite-code endpoint is not available.
      if (response.statusCode == 404) {
        return _linkClinicianLegacy(
          patientDeviceId: patientDeviceId,
          clinicianId: trimmedInput,
        );
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        _lastLinkError =
            'Link failed with HTTP ${response.statusCode} at ${ApiEndpointService.instance.baseUrl}.';
        return false;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        _lastLinkError = 'Link response payload was not valid JSON.';
        return false;
      }

      final clinicianId = decoded['clinician_id'];
      final publicKeyPem = decoded['clinician_public_key_pem'];
      if (clinicianId is! String || clinicianId.trim().isEmpty || publicKeyPem is! String || publicKeyPem.trim().isEmpty) {
        _lastLinkError = 'Clinician exists but has no public key registered.';
        return false;
      }

      await StorageService.instance.settingsBox.put(_linkedClinicianIdKey, clinicianId.trim());
      await StorageService.instance.settingsBox.put(_linkedClinicianPublicKeyKey, publicKeyPem.trim());
      _lastLinkError = null;
      return true;
    } catch (error) {
      _lastLinkError = 'Could not reach ${ApiEndpointService.instance.baseUrl}: $error';
      return false;
    }
  }

  Future<bool> _linkClinicianLegacy({
    required String patientDeviceId,
    required String clinicianId,
  }) async {
    final trimmedClinicianId = clinicianId.trim();
    if (trimmedClinicianId.isEmpty) {
      _lastLinkError = 'Clinician ID is required.';
      return false;
    }

    final legacyUri = ApiEndpointService.instance.buildUri('/clinicians/link');
    final legacyResponse = await ApiEndpointService.instance.post(
      legacyUri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(
        {
          'patient_device_id': patientDeviceId,
          'clinician_id': trimmedClinicianId,
        },
      ),
    );

    if (legacyResponse.statusCode < 200 || legacyResponse.statusCode >= 300) {
      _lastLinkError =
          'Link failed with HTTP ${legacyResponse.statusCode} at ${ApiEndpointService.instance.baseUrl}.';
      return false;
    }

    final decoded = jsonDecode(legacyResponse.body);
    if (decoded is! Map<String, dynamic>) {
      _lastLinkError = 'Link response payload was not valid JSON.';
      return false;
    }

    final resolvedClinicianId = decoded['clinician_id'];
    final publicKeyPem = decoded['clinician_public_key_pem'];
    if (resolvedClinicianId is! String ||
        resolvedClinicianId.trim().isEmpty ||
        publicKeyPem is! String ||
        publicKeyPem.trim().isEmpty) {
      _lastLinkError = 'Clinician exists but has no public key registered.';
      return false;
    }

    await StorageService.instance.settingsBox.put(
      _linkedClinicianIdKey,
      resolvedClinicianId.trim(),
    );
    await StorageService.instance.settingsBox.put(
      _linkedClinicianPublicKeyKey,
      publicKeyPem.trim(),
    );
    _lastLinkError = null;
    return true;
  }

  Future<bool> registerClinicianConnection({
    required String clinicianId,
    required String publicKeyPem,
  }) async {
    final trimmedId = clinicianId.trim();
    final trimmedPem = publicKeyPem.trim();
    if (trimmedId.isEmpty || trimmedPem.isEmpty) {
      return false;
    }

    final uri = ApiEndpointService.instance.buildUri('/clinicians/register');
    final response = await ApiEndpointService.instance.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(
        {
          'clinician_id': trimmedId,
          'public_key_pem': trimmedPem,
        },
      ),
    );

    return response.statusCode >= 200 && response.statusCode < 300;
  }

  Future<String> ensureClinicianSessionToken({required String clinicianId}) async {
    final trimmedId = clinicianId.trim();
    if (trimmedId.isEmpty) {
      throw ArgumentError('clinicianId is required');
    }

    final box = StorageService.instance.settingsBox;
    final existingJwt = (box.get(_clinicianJwtKey) as String?)?.trim();
    if (existingJwt != null && existingJwt.isNotEmpty) {
      return existingJwt;
    }

    final existingToken = (box.get('auth_access_token') as String?)?.trim();
    final role = (box.get('auth_role') as String?)?.trim();
    final boundClinicianId = (box.get('auth_clinician_id') as String?)?.trim();
    final expiresRaw = (box.get('auth_expires_at') as String?)?.trim();

    if (existingToken != null &&
        existingToken.isNotEmpty &&
        role == 'clinician' &&
        boundClinicianId == trimmedId &&
        expiresRaw != null) {
      final expiresAt = DateTime.tryParse(expiresRaw)?.toUtc();
      if (expiresAt != null && expiresAt.isAfter(DateTime.now().toUtc())) {
        await box.put(_clinicianJwtKey, existingToken);
        return existingToken;
      }
    }

    final demoToken =
        'demo-clinician-$trimmedId-${DateTime.now().millisecondsSinceEpoch}';
    final expiresAt = DateTime.now().toUtc().add(const Duration(days: 3650));
    await box.put(_clinicianJwtKey, demoToken);
    await box.put('auth_access_token', demoToken);
    await box.put('auth_role', 'clinician');
    await box.put('auth_clinician_id', trimmedId);
    await box.put('auth_expires_at', expiresAt.toIso8601String());
    return demoToken;
  }

  Future<String> getOrCreatePatientDeviceId() => _getOrCreatePatientDeviceId();

  Future<void> syncMoodTelemetry({required JournalEntry entry}) async {
    if (!_isClinicianOptInEnabled()) {
      return;
    }

    final clinicianId = linkedClinicianId;
    final clinicianPublicKey = _linkedClinicianPublicKey();
    if (clinicianId == null || clinicianPublicKey == null) {
      return;
    }

    final payload = <String, dynamic>{
      'event_type': 'mood_sync',
      'timestamp': entry.timestamp.toUtc().toIso8601String(),
      'mood_labels': entry.moodPath,
      'risk_flags': entry.riskFlags,
      'mood_score': entry.moodScore,
    };

    final lockedBox = ReportService.instance.buildLockedBox(
      summary: payload,
      clinicianPublicKeyPem: clinicianPublicKey,
    );

    await _postSecurePayload(
      path: '/telemetry/mood-events',
      clinicianId: clinicianId,
      lockedBox: lockedBox,
      moodSummary: <String, dynamic>{
        'timestamp': entry.timestamp.toUtc().toIso8601String(),
        'mood_score': entry.moodScore,
        'mood_labels': entry.moodPath,
        'risk_flags': entry.riskFlags,
      },
    );
  }

  Future<bool> shareEntryContent({required JournalEntry entry}) async {
    final clinicianId = linkedClinicianId;
    final clinicianPublicKey = _linkedClinicianPublicKey();
    if (clinicianId == null || clinicianPublicKey == null) {
      return false;
    }

    final payload = <String, dynamic>{
      'entry_id': entry.id,
      'timestamp': entry.timestamp.toUtc().toIso8601String(),
      'text': entry.text,
      'mood_labels': entry.moodPath,
      'risk_flags': entry.riskFlags,
    };

    final lockedBox = ReportService.instance.buildLockedBox(
      summary: payload,
      clinicianPublicKeyPem: clinicianPublicKey,
    );

    final ok = await _postSecurePayload(
      path: '/entries/share',
      clinicianId: clinicianId,
      lockedBox: lockedBox,
    );

    return ok;
  }

  Future<void> sendEmergencyAlert({
    required String triggerText,
    required List<String> riskFlags,
    required String source,
  }) async {
    if (!_isClinicianOptInEnabled()) {
      return;
    }

    final clinicianId = linkedClinicianId;
    final clinicianPublicKey = _linkedClinicianPublicKey();
    if (clinicianId == null || clinicianPublicKey == null) {
      return;
    }

    final textSnippet = triggerText.length > 180 ? '${triggerText.substring(0, 180)}...' : triggerText;
    final payload = <String, dynamic>{
      'severity': 'high',
      'source': source,
      'triggered_at': DateTime.now().toUtc().toIso8601String(),
      'risk_flags': riskFlags,
      'text_snippet': textSnippet,
    };

    final lockedBox = ReportService.instance.buildLockedBox(
      summary: payload,
      clinicianPublicKeyPem: clinicianPublicKey,
    );

    await _postSecurePayload(
      path: '/alerts/emergency',
      clinicianId: clinicianId,
      lockedBox: lockedBox,
    );
  }

  Future<bool> sendClinicianSignal({
    required String signalType,
    required Map<String, dynamic> payload,
  }) async {
    if (!_isClinicianOptInEnabled()) {
      return false;
    }

    final clinicianId = linkedClinicianId;
    final clinicianPublicKey = _linkedClinicianPublicKey();
    if (clinicianId == null || clinicianPublicKey == null) {
      return false;
    }

    final signalPayload = <String, dynamic>{
      'signal_type': signalType,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'payload': payload,
    };

    final lockedBox = ReportService.instance.buildLockedBox(
      summary: signalPayload,
      clinicianPublicKeyPem: clinicianPublicKey,
    );

    return _postSecurePayload(
      path: '/clinician/signal',
      clinicianId: clinicianId,
      lockedBox: lockedBox,
      signalType: signalType,
    );
  }

  Future<bool> _postSecurePayload({
    required String path,
    required String clinicianId,
    required Map<String, dynamic> lockedBox,
    Map<String, dynamic>? moodSummary,
    String? signalType,
  }) async {
    final patientDeviceId = await _getOrCreatePatientDeviceId();
    final uri = ApiEndpointService.instance.buildUri(path);
    final response = await ApiEndpointService.instance.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(
        {
          'patient_device_id': patientDeviceId,
          'clinician_id': clinicianId,
          'locked_box': lockedBox,
          ...?(moodSummary == null ? null : {'mood_summary': moodSummary}),
          ...?(signalType == null ? null : {'signal_type': signalType}),
        },
      ),
    );

    return response.statusCode >= 200 && response.statusCode < 300;
  }

  String? _linkedClinicianPublicKey() {
    final value = StorageService.instance.settingsBox.get(_linkedClinicianPublicKeyKey);
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  Future<String> _getOrCreatePatientDeviceId() async {
    final existing = StorageService.instance.settingsBox.get(_patientDeviceIdKey);
    if (existing is String && existing.trim().isNotEmpty) {
      return existing.trim();
    }

    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final id = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

    await StorageService.instance.settingsBox.put(_patientDeviceIdKey, id);
    return id;
  }

  bool _isClinicianOptInEnabled() {
    return StorageService.instance.readBoolSetting(
      _clinicianOptInSettingKey,
      fallback: false,
    );
  }
}
