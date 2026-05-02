import 'dart:convert';

import '../models/user_role.dart';
import 'api_endpoint_service.dart';
import 'storage_service.dart';

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.role,
    required this.phoneNumber,
    required this.userId,
    required this.expiresAt,
    this.clinicianId,
    this.patientDeviceId,
  });

  final String accessToken;
  final UserRole role;
  final String phoneNumber;
  final String userId;
  final DateTime expiresAt;
  final String? clinicianId;
  final String? patientDeviceId;

  bool get isExpired => expiresAt.isBefore(DateTime.now().toUtc());
}

class PhoneOtpAuthService {
  PhoneOtpAuthService._();

  static final PhoneOtpAuthService instance = PhoneOtpAuthService._();

  static const _tokenKey = 'auth_access_token';
  static const _roleKey = 'auth_role';
  static const _phoneKey = 'auth_phone_number';
  static const _userIdKey = 'auth_user_id';
  static const _expiresAtKey = 'auth_expires_at';
  static const _clinicianIdKey = 'auth_clinician_id';
  static const _patientDeviceIdKey = 'auth_patient_device_id';

  AuthSession? readSession() {
    final box = StorageService.instance.settingsBox;
    final token = (box.get(_tokenKey) as String?)?.trim() ?? '';
    final roleRaw = (box.get(_roleKey) as String?)?.trim() ?? '';
    final phone = (box.get(_phoneKey) as String?)?.trim() ?? '';
    final userId = (box.get(_userIdKey) as String?)?.trim() ?? '';
    final expiresRaw = (box.get(_expiresAtKey) as String?)?.trim() ?? '';

    if (token.isEmpty || roleRaw.isEmpty || phone.isEmpty || userId.isEmpty || expiresRaw.isEmpty) {
      return null;
    }

    final expiresAt = DateTime.tryParse(expiresRaw)?.toUtc();
    if (expiresAt == null) {
      return null;
    }

    final role = UserRoleX.fromStorage(roleRaw);
    if (role == UserRole.unset) {
      return null;
    }

    return AuthSession(
      accessToken: token,
      role: role,
      phoneNumber: phone,
      userId: userId,
      expiresAt: expiresAt,
      clinicianId: (box.get(_clinicianIdKey) as String?)?.trim(),
      patientDeviceId: (box.get(_patientDeviceIdKey) as String?)?.trim(),
    );
  }

  bool hasValidSessionForRole(
    UserRole role, {
    String? clinicianId,
    String? patientDeviceId,
  }) {
    final session = readSession();
    if (session == null || session.isExpired || session.role != role) {
      return false;
    }

    if (role == UserRole.clinician) {
      final expected = clinicianId?.trim();
      if (expected != null && expected.isNotEmpty && session.clinicianId != expected) {
        return false;
      }
    }

    if (role == UserRole.patient) {
      final expected = patientDeviceId?.trim();
      if (expected != null && expected.isNotEmpty && session.patientDeviceId != expected) {
        return false;
      }
    }

    return true;
  }

  Future<String> requestOtp({
    required String phoneNumber,
    required UserRole role,
    String? clinicianId,
    String? patientDeviceId,
  }) async {
    final normalizedPhone = _normalizePhone(phoneNumber);
    final payload = <String, dynamic>{
      'phone_number': normalizedPhone,
      'role': role.storageValue,
      if (clinicianId != null && clinicianId.trim().isNotEmpty)
        'clinician_id': clinicianId.trim(),
      if (patientDeviceId != null && patientDeviceId.trim().isNotEmpty)
        'patient_device_id': patientDeviceId.trim(),
    };

    final response = await ApiEndpointService.instance.post(
      ApiEndpointService.instance.buildUri('/auth/otp/start'),
      headers: const <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('OTP start failed (HTTP ${response.statusCode}): ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid OTP start response payload.');
    }

    final challengeId = (decoded['challenge_id'] as String?)?.trim() ?? '';
    if (challengeId.isEmpty) {
      throw Exception('OTP challenge ID missing in response.');
    }
    return challengeId;
  }

  Future<AuthSession> verifyOtp({
    required String challengeId,
    required String phoneNumber,
    required String otpCode,
  }) async {
    final payload = <String, dynamic>{
      'challenge_id': challengeId.trim(),
      'phone_number': _normalizePhone(phoneNumber),
      'otp_code': otpCode.trim(),
    };

    final response = await ApiEndpointService.instance.post(
      ApiEndpointService.instance.buildUri('/auth/otp/verify'),
      headers: const <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('OTP verify failed (HTTP ${response.statusCode}): ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid OTP verify response payload.');
    }

    final token = (decoded['access_token'] as String?)?.trim() ?? '';
    final expiresAtRaw = (decoded['expires_at'] as String?)?.trim() ?? '';
    final user = decoded['user'];
    if (token.isEmpty || expiresAtRaw.isEmpty || user is! Map<String, dynamic>) {
      throw Exception('OTP verify response missing auth data.');
    }

    final expiresAt = DateTime.tryParse(expiresAtRaw)?.toUtc();
    if (expiresAt == null) {
      throw Exception('Invalid auth expiry timestamp.');
    }

    final role = UserRoleX.fromStorage((user['role'] as String?)?.trim());
    if (role == UserRole.unset) {
      throw Exception('Invalid user role in auth response.');
    }

    final session = AuthSession(
      accessToken: token,
      role: role,
      phoneNumber: (user['phone_number'] as String?)?.trim() ?? '',
      userId: (user['user_id'] as String?)?.trim() ?? '',
      expiresAt: expiresAt,
      clinicianId: (user['clinician_id'] as String?)?.trim(),
      patientDeviceId: (user['patient_device_id'] as String?)?.trim(),
    );

    if (session.phoneNumber.isEmpty || session.userId.isEmpty) {
      throw Exception('Auth session payload missing required user fields.');
    }

    await _persistSession(session);
    return session;
  }

  Future<void> clearSession() async {
    final box = StorageService.instance.settingsBox;
    await box.delete(_tokenKey);
    await box.delete(_roleKey);
    await box.delete(_phoneKey);
    await box.delete(_userIdKey);
    await box.delete(_expiresAtKey);
    await box.delete(_clinicianIdKey);
    await box.delete(_patientDeviceIdKey);
    await box.delete('clinician_jwt');
  }

  Future<void> _persistSession(AuthSession session) async {
    final box = StorageService.instance.settingsBox;
    await box.put(_tokenKey, session.accessToken);
    await box.put(_roleKey, session.role.storageValue);
    await box.put(_phoneKey, session.phoneNumber);
    await box.put(_userIdKey, session.userId);
    await box.put(_expiresAtKey, session.expiresAt.toUtc().toIso8601String());

    if (session.clinicianId != null && session.clinicianId!.isNotEmpty) {
      await box.put(_clinicianIdKey, session.clinicianId);
      await box.put('clinician_jwt', session.accessToken);
      await box.put('clinician_id', session.clinicianId);
    }

    if (session.patientDeviceId != null && session.patientDeviceId!.isNotEmpty) {
      await box.put(_patientDeviceIdKey, session.patientDeviceId);
      await box.put('patient_device_id', session.patientDeviceId);
    }
  }

  String _normalizePhone(String phoneNumber) {
    final normalized = phoneNumber.trim().replaceAll(' ', '');
    if (normalized.isEmpty || !normalized.startsWith('+')) {
      throw Exception('Use phone number in E.164 format, e.g. +15551234567');
    }
    return normalized;
  }
}
