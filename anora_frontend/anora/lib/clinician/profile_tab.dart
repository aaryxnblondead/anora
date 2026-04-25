import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_role.dart';
import '../services/clinician_crypto_service.dart';
import '../services/storage_service.dart';
import '../state/clinician_state.dart';
import '../state/role_controller.dart';

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ClinicianProfile.fromStorage();
    final roleController = ref.read(roleProvider.notifier);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      children: [
        Text('Profile', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Identity',
          children: [
            _DisplayRow(label: 'Name', value: profile.name.isEmpty ? 'Not set' : profile.name),
            const Divider(),
            _DisplayRow(
              label: 'Credentials',
              value: profile.credentials.isEmpty ? 'Not set' : profile.credentials,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Your Clinician ID',
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0DED7)),
                color: Colors.white,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      profile.clinicianId.isEmpty ? 'Not generated' : profile.clinicianId,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: profile.clinicianId.isEmpty
                        ? null
                        : () async {
                            await Clipboard.setData(ClipboardData(text: profile.clinicianId));
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Clinician ID copied.')),
                            );
                          },
                    icon: const Icon(Icons.copy_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text('Share this ID with patients', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Encryption',
          children: [
            Row(
              children: [
                const Expanded(child: Text('RSA Keypair')),
                Icon(
                  profile.hasPrivateKey ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                  color: profile.hasPrivateKey
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: profile.publicKeyPem.isEmpty
                  ? null
                  : () => _showPublicKeySheet(context, profile.publicKeyPem),
              child: const Text('View Public Key'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _confirmRegenerate(context),
              child: const Text('Regenerate Keypair'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Session',
          children: [
            _SettingRow(
              title: 'Switch to Patient mode',
              subtitle: 'This will log you out of clinician mode.',
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                final shouldSwitch = await _showConfirmDialog(
                  context,
                  title: 'Switch to Patient mode?',
                  content: 'This will log you out of clinician mode.',
                );
                if (!context.mounted || !shouldSwitch) return;
                await roleController.setRole(UserRole.unset);
              },
            ),
            const Divider(),
            _HoldToConfirmButton(
              label: 'Hold 3 seconds to sign out / erase data',
              onConfirmed: () async {
                await StorageService.instance.eraseAllData();
                await roleController.clearRole();
              },
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showPublicKeySheet(BuildContext context, String pem) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Public Key', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              Container(
                constraints: const BoxConstraints(maxHeight: 280),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE0DED7)),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(pem, style: Theme.of(context).textTheme.bodySmall),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: pem));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Public key copied.')),
                  );
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copy'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmRegenerate(BuildContext context) async {
    final shouldRegenerate = await _showConfirmDialog(
      context,
      title: 'Regenerate keypair?',
      content: 'This will break decryption of existing reports. Are you sure?',
    );

    if (!context.mounted || !shouldRegenerate) return;

    try {
      await ClinicianCryptoService.instance.generateAndStoreKeypair();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keypair regenerated.')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not regenerate keypair: $error')),
      );
    }
  }

  Future<bool> _showConfirmDialog(
    BuildContext context, {
    required String title,
    required String content,
  }) async {
    final value = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    return value == true;
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
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

class _DisplayRow extends StatelessWidget {
  const _DisplayRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ],
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              trailing!,
            ],
          ],
        ),
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
                  color: const Color(0xFFF1F0EB),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Theme.of(context).colorScheme.error),
                ),
                child: Center(
                  child: Text(
                    widget.label,
                    style: Theme.of(context).textTheme.labelLarge,
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
                      color: Theme.of(context).colorScheme.error.withValues(alpha: 0.2),
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
