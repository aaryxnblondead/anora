import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';
import '../state/settings_controller.dart';

class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  bool _locked = false;
  bool _checking = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _evaluateLockState(requireAuth: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _evaluateLockState(requireAuth: false);
    }
  }

  Future<void> _evaluateLockState({required bool requireAuth}) async {
    final settings = ref.read(settingsControllerProvider);
    if (!settings.biometricsEnabled) {
      if (mounted) {
        setState(() => _locked = false);
      }
      return;
    }

    if (requireAuth || settings.autoLockEnabled) {
      if (mounted) {
        setState(() => _locked = true);
      }
    }
  }

  Future<void> _attemptUnlock() async {
    if (_checking) return;
    setState(() => _checking = true);

    final success = await AuthService.instance.authenticate(
      reason: 'Unlock Anora to continue your private journal.',
    );

    if (mounted) {
      setState(() {
        _checking = false;
        _locked = !success;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_locked) {
      return widget.child;
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F0EB),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  size: 38,
                  color: Color(0xFF5B6F8F),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Anora is locked',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Use Face ID, Touch ID, or device biometrics to continue.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _checking ? null : _attemptUnlock,
                  child: _checking
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Unlock'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
