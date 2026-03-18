import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/storage_service.dart';

const _biometricKey = 'setting_biometric';
const _autoLockKey = 'setting_autolock';
const _remindersKey = 'setting_reminders';
const _hapticsKey = 'setting_haptics';

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
}

class AppSettings {
  const AppSettings({
    required this.biometricsEnabled,
    required this.autoLockEnabled,
    required this.remindersEnabled,
    required this.hapticsEnabled,
  });

  factory AppSettings.initial() {
    return const AppSettings(
      biometricsEnabled: false,
      autoLockEnabled: true,
      remindersEnabled: true,
      hapticsEnabled: true,
    );
  }

  final bool biometricsEnabled;
  final bool autoLockEnabled;
  final bool remindersEnabled;
  final bool hapticsEnabled;

  AppSettings copyWith({
    bool? biometricsEnabled,
    bool? autoLockEnabled,
    bool? remindersEnabled,
    bool? hapticsEnabled,
  }) {
    return AppSettings(
      biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
      autoLockEnabled: autoLockEnabled ?? this.autoLockEnabled,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
    );
  }
}
