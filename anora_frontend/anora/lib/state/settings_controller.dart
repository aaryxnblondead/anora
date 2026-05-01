import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/storage_service.dart';

const _biometricKey = 'setting_biometric';
const _autoLockKey = 'setting_autolock';
const _remindersKey = 'setting_reminders';
const _hapticsKey = 'setting_haptics';
const _clinicianOptInKey = 'setting_clinician_opt_in';
const _autoUnstuckKey = 'setting_auto_unstuck';

final settingsControllerProvider =
    StateNotifierProvider<SettingsController, AppSettings>(
  (ref) => SettingsController(StorageService.instance),
);

class SettingsController extends StateNotifier<AppSettings> {
  SettingsController(this._storage) : super(AppSettings.initial()) {
    _loadFromStorage();
  }

  final StorageService _storage;

  void _loadFromStorage() {
    state = state.copyWith(
      biometricsEnabled:
          _storage.readBoolSetting(_biometricKey, fallback: false),
      autoLockEnabled: _storage.readBoolSetting(_autoLockKey, fallback: true),
      remindersEnabled: _storage.readBoolSetting(_remindersKey, fallback: true),
      hapticsEnabled: _storage.readBoolSetting(_hapticsKey, fallback: true),
      clinicianOptIn: _storage.readBoolSetting(_clinicianOptInKey, fallback: false),
      autoUnstuckEnabled: _storage.readBoolSetting(_autoUnstuckKey, fallback: false),
    );
  }

  Future<void> setBiometrics(bool value) async {
    state = state.copyWith(biometricsEnabled: value);
    await _storage.writeBoolSetting(_biometricKey, value);
  }

  Future<void> setAutoLock(bool value) async {
    state = state.copyWith(autoLockEnabled: value);
    await _storage.writeBoolSetting(_autoLockKey, value);
  }

  Future<void> setReminders(bool value) async {
    state = state.copyWith(remindersEnabled: value);
    await _storage.writeBoolSetting(_remindersKey, value);
  }

  Future<void> setHaptics(bool value) async {
    state = state.copyWith(hapticsEnabled: value);
    await _storage.writeBoolSetting(_hapticsKey, value);
  }

  Future<void> setClinicianOptIn(bool value) async {
    state = state.copyWith(clinicianOptIn: value);
    await _storage.writeBoolSetting(_clinicianOptInKey, value);
  }

  Future<void> setAutoUnstuck(bool value) async {
    state = state.copyWith(autoUnstuckEnabled: value);
    await _storage.writeBoolSetting(_autoUnstuckKey, value);
  }
}

class AppSettings {
  const AppSettings({
    required this.biometricsEnabled,
    required this.autoLockEnabled,
    required this.remindersEnabled,
    required this.hapticsEnabled,
    required this.clinicianOptIn,
    required this.autoUnstuckEnabled,
  });

  factory AppSettings.initial() {
    return const AppSettings(
      biometricsEnabled: false,
      autoLockEnabled: true,
      remindersEnabled: true,
      hapticsEnabled: true,
      clinicianOptIn: false,
      autoUnstuckEnabled: false,
    );
  }

  final bool biometricsEnabled;
  final bool autoLockEnabled;
  final bool remindersEnabled;
  final bool hapticsEnabled;
  final bool clinicianOptIn;
  final bool autoUnstuckEnabled;

  AppSettings copyWith({
    bool? biometricsEnabled,
    bool? autoLockEnabled,
    bool? remindersEnabled,
    bool? hapticsEnabled,
    bool? clinicianOptIn,
    bool? autoUnstuckEnabled,
  }) {
    return AppSettings(
      biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
      autoLockEnabled: autoLockEnabled ?? this.autoLockEnabled,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      clinicianOptIn: clinicianOptIn ?? this.clinicianOptIn,
      autoUnstuckEnabled: autoUnstuckEnabled ?? this.autoUnstuckEnabled,
    );
  }
}
