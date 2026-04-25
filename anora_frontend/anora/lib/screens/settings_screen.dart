import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/share_report_screen.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../state/settings_controller.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Future<void> _showEraseDialog() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EraseSheet(
        onErase: () async {
          await StorageService.instance.eraseAllData();
          if (!context.mounted) return;
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All local data erased.')),
          );
        },
      ),
    );
  }

  Future<void> _showExportPlaceholder() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Encrypted export is coming soon.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(
            'Your privacy stays on-device. Adjust your comfort level here.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          _SectionCard(
            title: 'Privacy',
            children: [
              _SettingRow(
                title: 'Face/Touch unlock',
                subtitle: 'Require device authentication to open the app.',
                trailing: Switch.adaptive(
                  value: settings.biometricsEnabled,
                  onChanged: (value) async {
                    if (value) {
                      final available =
                          await AuthService.instance.canCheckBiometrics();
                      if (!available) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Biometrics are not available.'),
                          ),
                        );
                        return;
                      }

                      final authenticated =
                          await AuthService.instance.authenticate(
                        reason: 'Enable biometric unlock for Anora.',
                      );

                      if (!authenticated) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Authentication canceled.'),
                          ),
                        );
                        return;
                      }
                    }

                    await controller.setBiometrics(value);
                    if (settings.hapticsEnabled || value) {
                      HapticFeedback.selectionClick();
                    }
                  },
                ),
              ),
              const Divider(),
              _SettingRow(
                title: 'Auto-lock',
                subtitle: 'Lock the app after 2 minutes of inactivity.',
                trailing: Switch.adaptive(
                  value: settings.autoLockEnabled,
                  onChanged: (value) async {
                    await controller.setAutoLock(value);
                    if (settings.hapticsEnabled) {
                      HapticFeedback.selectionClick();
                    }
                  },
                ),
              ),
              const Divider(),
              _SettingRow(
                title: 'Share encrypted report',
                subtitle: 'Send a privacy-preserving summary to your clinician.',
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ShareReportScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Wellness',
            children: [
              _SettingRow(
                title: 'Daily check-in reminder',
                subtitle: 'Gentle nudge at your preferred time.',
                trailing: Switch.adaptive(
                  value: settings.remindersEnabled,
                  onChanged: (value) async {
                    await controller.setReminders(value);
                    if (settings.hapticsEnabled) {
                      HapticFeedback.selectionClick();
                    }
                  },
                ),
              ),
              const Divider(),
              _SettingRow(
                title: 'Haptic feedback',
                subtitle: 'Subtle taps for saves and mood selection.',
                trailing: Switch.adaptive(
                  value: settings.hapticsEnabled,
                  onChanged: (value) async {
                    await controller.setHaptics(value);
                    if (value) {
                      HapticFeedback.selectionClick();
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Storage',
            children: [
              _SettingRow(
                title: 'Export encrypted backup',
                subtitle: 'Save a local encrypted file to your device.',
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _showExportPlaceholder,
              ),
              const Divider(),
              _SettingRow(
                title: 'Erase all journal data',
                subtitle: 'Permanently delete local entries.',
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _showEraseDialog,
                accentColor: const Color(0xFFE38B7C),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'About',
            children: [
              _SettingRow(
                title: 'Version',
                subtitle: '1.0.0 (MVP)',
                trailing: const SizedBox.shrink(),
              ),
              const Divider(),
              _SettingRow(
                title: 'Privacy promise',
                subtitle: 'All text stays on your device.',
                trailing: const Icon(Icons.lock_outline_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F0EB),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    this.accentColor,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: accentColor,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: trailing,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EraseSheet extends StatelessWidget {
  const _EraseSheet({required this.onErase});

  final Future<void> Function() onErase;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: 24 + MediaQuery.of(context).padding.bottom,
        top: 24,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF7F6F2),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Erase all data', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'This permanently removes every journal entry stored on this device. '
            'Your encryption key is destroyed, so the data cannot be recovered.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          _HoldToConfirmButton(
            label: 'Hold 3 seconds to erase',
            onConfirmed: onErase,
          ),
          const SizedBox(height: 12),
          Text(
            'Tip: Export an encrypted backup first if you might want to restore later.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _HoldToConfirmButton extends StatefulWidget {
  const _HoldToConfirmButton({required this.label, required this.onConfirmed});

  final String label;
  final Future<void> Function() onConfirmed;

  @override
  State<_HoldToConfirmButton> createState() => _HoldToConfirmButtonState();
}

class _HoldToConfirmButtonState extends State<_HoldToConfirmButton> {
  static const _holdDuration = Duration(seconds: 3);

  Timer? _timer;
  double _progress = 0;
  bool _confirmed = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startHolding() {
    if (_timer != null) return;
    _confirmed = false;
    _progress = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 60), (timer) {
      setState(() {
        _progress += 60 / _holdDuration.inMilliseconds;
        if (_progress >= 1) {
          _progress = 1;
          _timer?.cancel();
          _timer = null;
          _confirmed = true;
        }
      });

      if (_confirmed) {
        widget.onConfirmed();
      }
    });
  }

  void _stopHolding() {
    _timer?.cancel();
    _timer = null;
    if (!_confirmed) {
      setState(() => _progress = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onLongPressStart: (_) => _startHolding(),
          onLongPressEnd: (_) => _stopHolding(),
          onLongPressCancel: _stopHolding,
          child: Stack(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFE6E4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE38B7C)),
                ),
                child: Center(
                  child: Text(
                    widget.label,
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: const Color(0xFF9C4B3F)),
                  ),
                ),
              ),
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 60),
                      width: constraints.maxWidth * _progress,
                      color: const Color(0xFFE38B7C).withValues(alpha: 0.25),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
