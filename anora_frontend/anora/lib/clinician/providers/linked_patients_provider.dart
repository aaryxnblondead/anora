import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/clinician_push_service.dart';
import '../../services/storage_service.dart';

class LinkedPatientsState {
  const LinkedPatientsState({
    this.patients = const [],
    this.isLoading = false,
    this.error,
    this.lastSyncAt,
  });

  final List<LinkedPatientEntry> patients;
  final bool isLoading;
  final String? error;
  final DateTime? lastSyncAt;

  int get totalLinked => patients.length;
  int get withRiskFlags =>
      patients.where((p) => p.latestMood?.hasRiskFlags == true).length;
  int get withMoodData => patients.where((p) => p.hasMoodData).length;

  LinkedPatientsState copyWith({
    List<LinkedPatientEntry>? patients,
    bool? isLoading,
    String? error,
    DateTime? lastSyncAt,
  }) {
    return LinkedPatientsState(
      patients: patients ?? this.patients,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    );
  }
}

class LinkedPatientsNotifier extends StateNotifier<LinkedPatientsState> {
  LinkedPatientsNotifier(this._storage) : super(const LinkedPatientsState()) {
    _loadFromCache();
  }

  final StorageService _storage;
  static const _cacheKey = 'linked_patients_cache_v1';

  Future<void> sync() async {
    final clinicianId =
        (_storage.settingsBox.get('clinician_id') as String?)?.trim();
    if (clinicianId == null || clinicianId.isEmpty) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final entries =
          await ClinicianInboxSyncService.instance.fetchLinkedPatients(
        clinicianId: clinicianId,
      );

      // Preserve custom labels set by the clinician
      final existingLabels = <String, String>{
        for (final p in state.patients) p.patientDeviceId: p.patientLabel,
      };

      final merged = entries.map((e) {
        final label = existingLabels[e.patientDeviceId] ?? e.patientLabel;
        return e.copyWith(patientLabel: label);
      }).toList();

      // Sort: patients with risk flags first, then by last mood time
      merged.sort((a, b) {
        final aRisk = a.latestMood?.hasRiskFlags == true ? 0 : 1;
        final bRisk = b.latestMood?.hasRiskFlags == true ? 0 : 1;
        if (aRisk != bRisk) return aRisk.compareTo(bRisk);
        final aTime = a.latestMood?.lastMoodAt ?? a.linkedAt;
        final bTime = b.latestMood?.lastMoodAt ?? b.linkedAt;
        return bTime.compareTo(aTime);
      });

      state = state.copyWith(
        patients: merged,
        isLoading: false,
        lastSyncAt: DateTime.now().toUtc(),
      );
      await _persistCache();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Error fetching feed: $e',
      );
    }
  }

  Future<void> updatePatientLabel(String deviceId, String label) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return;
    final updated = state.patients
        .map((p) => p.patientDeviceId == deviceId
            ? p.copyWith(patientLabel: trimmed)
            : p)
        .toList();
    state = state.copyWith(patients: updated);
    await _persistCache();
  }

  void _loadFromCache() {
    try {
      final raw = _storage.settingsBox.get(_cacheKey);
      if (raw is! String || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final patients = decoded
          .whereType<Map>()
          .map((m) => LinkedPatientEntry.fromJson(
                Map<String, dynamic>.from(m),
              ))
          .toList();
      state = state.copyWith(patients: patients);
    } catch (_) {
      // Cache corrupt — start fresh, will sync on next resume
    }
  }

  Future<void> _persistCache() async {
    try {
      final data = state.patients.map((p) => {
            'patient_device_id': p.patientDeviceId,
            'patient_label': p.patientLabel,
            'linked_at': p.linkedAt.toIso8601String(),
            'latest_mood': p.latestMood == null
                ? null
                : {
                    'mood_score': p.latestMood!.moodScore,
                    'mood_labels': p.latestMood!.moodLabels,
                    'risk_flags': p.latestMood!.riskFlags,
                    'last_mood_at':
                        p.latestMood!.lastMoodAt.toIso8601String(),
                  },
          }).toList();
      await _storage.settingsBox.put(_cacheKey, jsonEncode(data));
    } catch (_) {}
  }
}

final linkedPatientsProvider =
    StateNotifierProvider<LinkedPatientsNotifier, LinkedPatientsState>(
  (ref) => LinkedPatientsNotifier(StorageService.instance),
);