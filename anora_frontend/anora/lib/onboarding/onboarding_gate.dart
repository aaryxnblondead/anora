import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../clinician/clinician_shell.dart';
import '../main.dart';
import '../models/user_role.dart';
import '../services/storage_service.dart';
import '../state/role_controller.dart';
import '../widgets/app_lock_gate.dart';
import 'clinician_onboarding_screen.dart';
import 'patient_onboarding_screen.dart';
import 'role_selection_screen.dart';

class OnboardingGate extends ConsumerWidget {
  const OnboardingGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(roleProvider);

    switch (role) {
      case UserRole.unset:
        return const RoleSelectionScreen();
      case UserRole.patient:
        return const _PatientOnboardingGate();
      case UserRole.clinician:
        return const ClinicianOnboardingGate();
    }
  }
}

class _PatientOnboardingGate extends StatelessWidget {
  const _PatientOnboardingGate();

  @override
  Widget build(BuildContext context) {
    final settingsBox = StorageService.instance.settingsBox;
    return ValueListenableBuilder<Box<dynamic>>(
      valueListenable: settingsBox.listenable(keys: const ['patient_onboarding_complete']),
      builder: (context, _, __) {
        final isComplete = settingsBox.get('patient_onboarding_complete', defaultValue: false) == true;
        if (!isComplete) {
          return const PatientOnboardingScreen();
        }
        return const AppLockGate(child: AppShell());
      },
    );
  }
}

class ClinicianOnboardingGate extends ConsumerWidget {
  const ClinicianOnboardingGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsBox = StorageService.instance.settingsBox;
    return ValueListenableBuilder<Box<dynamic>>(
      valueListenable: settingsBox.listenable(keys: const ['clinician_onboarding_complete']),
      builder: (context, _, __) {
        final isComplete = settingsBox.get('clinician_onboarding_complete', defaultValue: false) == true;
        if (!isComplete) {
          return const ClinicianOnboardingScreen();
        }
        return const ClinicianShell();
      },
    );
  }
}
