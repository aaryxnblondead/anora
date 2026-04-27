import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'api_endpoint_service.dart';

class ClinicianPushRegistrationService {
  ClinicianPushRegistrationService._();

  static final ClinicianPushRegistrationService instance =
      ClinicianPushRegistrationService._();

  static const MethodChannel _methodChannel = MethodChannel('com.anora.push');

  Future<void> registerForClinician({required String clinicianId}) async {
    final trimmedClinicianId = clinicianId.trim();
    if (trimmedClinicianId.isEmpty) {
      return;
    }

    if (!_supportsPushNotifications()) {
      return;
    }

    final token = await _fetchNativeDeviceToken();
    if (token != null && token.isNotEmpty) {
      await _syncToken(trimmedClinicianId, token);
    }
  }

  Future<String?> _fetchNativeDeviceToken() async {
    if (kIsWeb) {
      return null;
    }

    try {
      final token = await _methodChannel.invokeMethod<String>('getDeviceToken');
      final trimmed = token?.trim() ?? '';
      return trimmed.isEmpty ? null : trimmed;
    } on PlatformException {
      return null;
    }
  }

  Future<void> _syncToken(String clinicianId, String token) async {
    if (token.trim().isEmpty) {
      return;
    }

    if (!_supportsPushNotifications()) {
      return;
    }

    final response = await ApiEndpointService.instance.post(
      ApiEndpointService.instance.buildUri('/clinicians/push-tokens'),
      headers: const <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{
        'clinician_id': clinicianId,
        'device_token': token,
        'platform': _platformLabel(),
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }

  bool _supportsPushNotifications() {
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.android || TargetPlatform.macOS => true,
      TargetPlatform.fuchsia ||
      TargetPlatform.linux ||
      TargetPlatform.windows => false,
    };
  }

  String _platformLabel() {
    if (kIsWeb) {
      return 'web';
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.linux => 'linux',
      TargetPlatform.windows => 'windows',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }
}
