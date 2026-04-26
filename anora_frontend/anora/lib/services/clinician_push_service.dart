import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;

import '../utils/env.dart';
import 'storage_service.dart';

@pragma('vm:entry-point')
Future<void> anoraFirebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await ClinicianPushService.instance.ensureFirebaseInitialized();
  } catch (_) {
    // Keep background handler non-fatal.
  }
}

class ClinicianPushService {
  ClinicianPushService._();

  static final ClinicianPushService instance = ClinicianPushService._();

  final StreamController<RemoteMessage> _foregroundController =
      StreamController<RemoteMessage>.broadcast();
  final StreamController<RemoteMessage> _openedAppController =
      StreamController<RemoteMessage>.broadcast();

  Stream<RemoteMessage> get foregroundMessages => _foregroundController.stream;
  Stream<RemoteMessage> get openedAppMessages => _openedAppController.stream;

  bool _firebaseReady = false;
  bool _messagingHooksBound = false;

  Future<void> ensureFirebaseInitialized() async {
    if (_firebaseReady) return;

    try {
      if (Firebase.apps.isNotEmpty) {
        _firebaseReady = true;
      } else {
        await Firebase.initializeApp();
        _firebaseReady = true;
      }
    } catch (_) {
      final hasDartDefines = Env.firebaseApiKey.isNotEmpty &&
          Env.firebaseAppId.isNotEmpty &&
          Env.firebaseMessagingSenderId.isNotEmpty &&
          Env.firebaseProjectId.isNotEmpty;

      if (!hasDartDefines) {
        _firebaseReady = false;
        return;
      }

      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: Env.firebaseApiKey,
          appId: Env.firebaseAppId,
          messagingSenderId: Env.firebaseMessagingSenderId,
          projectId: Env.firebaseProjectId,
          storageBucket: Env.firebaseStorageBucket.isEmpty
              ? null
              : Env.firebaseStorageBucket,
          iosBundleId:
              Env.firebaseIosBundleId.isEmpty ? null : Env.firebaseIosBundleId,
        ),
      );
      _firebaseReady = true;
    }

    if (!_messagingHooksBound) {
      FirebaseMessaging.onBackgroundMessage(anoraFirebaseMessagingBackgroundHandler);
      FirebaseMessaging.onMessage.listen((message) {
        _foregroundController.add(message);
      });
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _openedAppController.add(message);
      });
      _messagingHooksBound = true;
    }
  }

  Future<void> startForClinician() async {
    await ensureFirebaseInitialized();
    if (!_firebaseReady) return;

    final clinicianId = _clinicianId();
    if (clinicianId == null) return;

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    final token = await messaging.getToken();
    if (token != null && token.isNotEmpty) {
      await _registerToken(
        clinicianId: clinicianId,
        token: token,
        platform: 'flutter',
      );
    }

    messaging.onTokenRefresh.listen((newToken) async {
      if (newToken.isEmpty) return;
      await _registerToken(
        clinicianId: clinicianId,
        token: newToken,
        platform: 'flutter',
      );
    });
  }

  Future<void> _registerToken({
    required String clinicianId,
    required String token,
    required String platform,
  }) async {
    final uri = Uri.parse('${Env.apiBaseUrl}/clinicians/fcm-tokens/register');
    await http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(
        {
          'clinician_id': clinicianId,
          'device_token': token,
          'platform': platform,
        },
      ),
    );
  }

  String? _clinicianId() {
    final value = StorageService.instance.settingsBox.get('clinician_id');
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }
}
