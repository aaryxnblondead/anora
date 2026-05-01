import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/share_report_screen.dart';
import '../services/api_endpoint_service.dart';
import '../services/auth_service.dart';
import '../services/secure_link_service.dart';
import '../services/storage_service.dart';
import '../state/settings_controller.dart';
import '../theme/anora_theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _inviteCodeController;
  bool _isLinking = false;

  @override
  void initState() {
    super.initState();
    _inviteCodeController = TextEditingController(
      text: '',
    );
  }

  @override
  void dispose() {
    _inviteCodeController.dispose();
    super.dispose();
  }

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
      const SnackBar(content: Text('Private export is coming soon.')),
    );
  }

  Future<void> _showLinkClinicianDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Private Connection'),
        content: TextFormField(
          controller: _inviteCodeController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Clinician Invite Code',
            hintText: 'Enter 6-digit code',
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isLinking ? null : () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _isLinking
                ? null
                : () async {
                    final code = _inviteCodeController.text.trim();
                    if (code.isEmpty) return;
                    setState(() => _isLinking = true);
                    bool ok;
                    try {
                      ok = await SecureLinkService.instance.linkClinicianWithCode(code);
                    } catch (_) {
                      ok = false;
                    }
                    if (!mounted) return;
                    setState(() => _isLinking = false);
                    if (ctx.mounted) {
                      Navigator.of(ctx).pop();
                      _inviteCodeController.clear();
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? 'Securely linked to your clinician.'
                              : (SecureLinkService.instance.lastLinkError ?? 'Could not link right now. Check the code and try again.'),
                        ),
                      ),
                    );
                  },
            child: Text(_isLinking ? 'Linking...' : 'Link'),
          ),
        ],
      ),
    );
  }

  Future<void> _showApiEndpointDialog() async {
    final endpointController = TextEditingController(
      text: ApiEndpointService.instance.overrideBaseUrl ?? '',
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        var isSaving = false;
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Backend API endpoint'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: endpointController,
                    autofocus: true,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Base URL (http/https)',
                      hintText: 'https://your-api.example.com',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Leave blank to use the build-time API_BASE_URL.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(this.context);
                          setLocalState(() => isSaving = true);
                          final rawValue = endpointController.text.trim();

                          try {
                            await ApiEndpointService.instance.setOverrideBaseUrl(
                              rawValue.isEmpty ? null : rawValue,
                            );
                            await ApiEndpointService.instance.ping();

                            if (!mounted) return;
                            setState(() {});
                            if (ctx.mounted) {
                              Navigator.of(ctx).pop();
                            }
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Connected to ${ApiEndpointService.instance.baseUrl}.',
                                ),
                              ),
                            );
                          } catch (error) {
                            if (!mounted) return;
                            setLocalState(() => isSaving = false);
                            messenger.showSnackBar(
                              SnackBar(content: Text('Endpoint check failed: $error')),
                            );
                          }
                        },
                  child: Text(isSaving ? 'Saving...' : 'Save & test'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final linkedClinicianId = SecureLinkService.instance.linkedClinicianId;
    final activeApiBaseUrl = ApiEndpointService.instance.baseUrl;
    final apiOverride = ApiEndpointService.instance.overrideBaseUrl;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
        children: [
          const AnoraStaggeredReveal(
            order: 0,
            child: AnoraScreenHeader(
              title: 'Settings',
              subtitle: 'Tune privacy, security, and wellness preferences for your daily flow.',
            ),
          ),
          const SizedBox(height: 20),
          AnoraStaggeredReveal(
            order: 1,
            child: _SectionCard(
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
                  title: linkedClinicianId == null ? 'Private Connection' : 'Securely Linked',
                  subtitle: linkedClinicianId == null
                      ? 'Link your clinician by ID.'
                      : 'Connected to clinician ID: $linkedClinicianId',
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _showLinkClinicianDialog,
                ),
                const Divider(),
                _SettingRow(
                  title: 'Share private summary',
                  subtitle: 'Send a privacy-preserving summary to your clinician.',
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ShareReportScreen()),
                  ),
                ),
                const Divider(),
                _SettingRow(
                  title: 'Allow clinician signals',
                  subtitle: 'Opt in to send brief alerts to your clinician when repeated high-distress sessions occur.',
                  trailing: Switch.adaptive(
                    value: settings.clinicianOptIn,
                    onChanged: (value) async {
                      await controller.setClinicianOptIn(value);
                      if (settings.hapticsEnabled && value) {
                        HapticFeedback.selectionClick();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AnoraStaggeredReveal(
            order: 2,
            child: _SectionCard(
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
                title: 'Start Unstuck automatically',
                subtitle: 'When enabled, a short Unstuck flow opens after a moderate-risk journal entry.',
                trailing: Switch.adaptive(
                  value: settings.autoUnstuckEnabled,
                  onChanged: (value) async {
                    await controller.setAutoUnstuck(value);
                    if (settings.hapticsEnabled && value) {
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
          ),
          const SizedBox(height: 16),
          AnoraStaggeredReveal(
            order: 3,
            child: _SectionCard(
            title: 'Storage',
            children: [
              _SettingRow(
                title: 'Backend API endpoint',
                subtitle: apiOverride == null
                    ? 'Using build URL: $activeApiBaseUrl'
                    : 'Using local override: $activeApiBaseUrl',
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _showApiEndpointDialog,
              ),
              const Divider(),
              _SettingRow(
                title: 'Export private backup',
                subtitle: 'Save a protected local file to your device.',
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
          ),
          const SizedBox(height: 16),
          AnoraStaggeredReveal(
            order: 4,
            child: const _SectionCard(
            title: 'About',
            children: [
              _SettingRow(
                title: 'Version',
                subtitle: '1.0.0 (MVP)',
                trailing: SizedBox.shrink(),
              ),
              Divider(),
              _SettingRow(
                title: 'Privacy promise',
                subtitle: 'All text stays on your device.',
                trailing: Icon(Icons.lock_outline_rounded),
              ),
            ],
            ),
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
    return AnoraSectionCard(
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
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
        color: Colors.white,
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
            'Your secure local vault is removed, so the data cannot be recovered.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          _HoldToConfirmButton(
            label: 'Hold 3 seconds to erase',
            onConfirmed: onErase,
          ),
          const SizedBox(height: 12),
          Text(
            'Tip: Export a private backup first if you might want to restore later.',
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
