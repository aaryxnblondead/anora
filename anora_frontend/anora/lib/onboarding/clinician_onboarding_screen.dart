import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/clinician_crypto_service.dart';
import '../services/storage_service.dart';

class ClinicianOnboardingScreen extends StatefulWidget {
  const ClinicianOnboardingScreen({super.key});

  @override
  State<ClinicianOnboardingScreen> createState() => _ClinicianOnboardingScreenState();
}

class _ClinicianOnboardingScreenState extends State<ClinicianOnboardingScreen> {
  final PageController _pageController = PageController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _credentialsController = TextEditingController();
  final TextEditingController _importPrivateKeyController = TextEditingController();

  final Map<String, String> _formData = <String, String>{};

  int _pageIndex = 0;
  bool _isBusy = false;
  bool _showImportField = false;
  String? _publicKeyPem;
  String? _clinicianId;

  @override
  void initState() {
    super.initState();
    final box = StorageService.instance.settingsBox;
    _nameController.text = (box.get('clinician_name') as String?) ?? '';
    _credentialsController.text = (box.get('clinician_credentials') as String?) ?? '';
    _publicKeyPem = ClinicianCryptoService.instance.getPublicKeyPem();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _credentialsController.dispose();
    _importPrivateKeyController.dispose();
    super.dispose();
  }

  Future<void> _nextPage() async {
    await _pageController.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _saveIdentityAndContinue() async {
    final name = _nameController.text.trim();
    final credentials = _credentialsController.text.trim();
    if (name.isEmpty) return;

    try {
      await StorageService.instance.settingsBox.put('clinician_name', name);
      await StorageService.instance.settingsBox.put('clinician_credentials', credentials);
      _formData['clinician_name'] = name;
      _formData['clinician_credentials'] = credentials;
      if (!mounted) return;
      await _nextPage();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save profile: $error')),
      );
    }
  }

  Future<void> _generateKeypair() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      await ClinicianCryptoService.instance.generateAndStoreKeypair();
      if (!mounted) return;
      setState(() => _publicKeyPem = ClinicianCryptoService.instance.getPublicKeyPem());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('RSA keypair generated and stored securely.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Key generation failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _importPrivateKey() async {
    final pem = _importPrivateKeyController.text.trim();
    if (pem.isEmpty) return;
    setState(() => _isBusy = true);
    try {
      await ClinicianCryptoService.instance.validateAndStorePrivateKey(pem);
      if (!mounted) return;
      setState(() => _publicKeyPem = ClinicianCryptoService.instance.getPublicKeyPem());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Private key imported and validated.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _prepareClinicianId() async {
    if (_clinicianId != null && _clinicianId!.isNotEmpty) {
      return;
    }

    final box = StorageService.instance.settingsBox;
    final current = box.get('clinician_id') as String?;
    if (current != null && current.isNotEmpty) {
      setState(() => _clinicianId = current);
      return;
    }

    final generated = _uuidV4();
    await box.put('clinician_id', generated);
    if (!mounted) return;
    setState(() => _clinicianId = generated);
  }

  Future<void> _completeOnboarding() async {
    try {
      await StorageService.instance.settingsBox.put('clinician_onboarding_complete', true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not complete onboarding: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 14),
            _StepDots(currentIndex: _pageIndex),
            const SizedBox(height: 12),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) {
                  setState(() => _pageIndex = index);
                  if (index == 2) {
                    _prepareClinicianId();
                  }
                },
                children: [
                  _IdentityStep(
                    nameController: _nameController,
                    credentialsController: _credentialsController,
                    onNext: _saveIdentityAndContinue,
                  ),
                  _KeyStep(
                    isBusy: _isBusy,
                    showImportField: _showImportField,
                    importController: _importPrivateKeyController,
                    publicKeyPem: _publicKeyPem,
                    onGenerate: _generateKeypair,
                    onImportToggle: () => setState(() => _showImportField = !_showImportField),
                    onImport: _importPrivateKey,
                    onNext: ClinicianCryptoService.instance.hasKeypair ? _nextPage : null,
                  ),
                  _ClinicianIdStep(
                    clinicianId: _clinicianId,
                    onCopy: () async {
                      final id = _clinicianId;
                      if (id == null || id.isEmpty) return;
                      await Clipboard.setData(ClipboardData(text: id));
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Clinician ID copied.')),
                      );
                    },
                    onNext: _nextPage,
                  ),
                  _ReadyStep(onFinish: _completeOnboarding),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.currentIndex});

  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        4,
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: currentIndex == index ? 18 : 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: currentIndex == index ? theme.colorScheme.primary : const Color(0xFFE0DED7),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

class _IdentityStep extends StatelessWidget {
  const _IdentityStep({
    required this.nameController,
    required this.credentialsController,
    required this.onNext,
  });

  final TextEditingController nameController;
  final TextEditingController credentialsController;
  final Future<void> Function() onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Your Identity', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text('Set up your profile', style: theme.textTheme.bodyLarge),
          const SizedBox(height: 16),
          TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Full name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: credentialsController,
            decoration: const InputDecoration(
              labelText: 'Credentials / specialty',
              hintText: 'e.g. MD, Psychiatry',
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Stored locally only. Never sent to any server.',
            style: theme.textTheme.bodySmall,
          ),
          const Spacer(),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: nameController,
            builder: (context, value, child) {
              return FilledButton(
                onPressed: value.text.trim().isEmpty ? null : onNext,
                child: const Text('Next'),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _KeyStep extends StatelessWidget {
  const _KeyStep({
    required this.isBusy,
    required this.showImportField,
    required this.importController,
    required this.publicKeyPem,
    required this.onGenerate,
    required this.onImportToggle,
    required this.onImport,
    required this.onNext,
  });

  final bool isBusy;
  final bool showImportField;
  final TextEditingController importController;
  final String? publicKeyPem;
  final Future<void> Function() onGenerate;
  final VoidCallback onImportToggle;
  final Future<void> Function() onImport;
  final Future<void> Function()? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Your Encryption Keys', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Secure your reports',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            'Anora uses RSA-2048 to encrypt patient summaries only you can read.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _OptionCard(
            title: 'Generate on device',
            child: FilledButton(
              onPressed: isBusy ? null : onGenerate,
              child: Text(isBusy ? 'Working...' : 'Generate RSA Keypair'),
            ),
          ),
          const SizedBox(height: 12),
          _OptionCard(
            title: 'Import existing',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton(
                  onPressed: isBusy ? null : onImportToggle,
                  child: const Text('Import Private Key'),
                ),
                if (showImportField) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: importController,
                    minLines: 8,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      hintText: 'Paste private key PEM here',
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: isBusy ? null : onImport,
                    child: const Text('Validate and Store'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (publicKeyPem != null && publicKeyPem!.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F0EB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0DED7)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Keypair generated and stored securely.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text('Your Public Key', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(publicKeyPem!, style: theme.textTheme.bodySmall),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(ClipboardData(text: publicKeyPem!));
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Public key copied.')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy Public Key'),
                  ),
                  Text(
                    'Share this with your patients so they can encrypt reports for you.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          const Spacer(),
          FilledButton(
            onPressed: onNext,
            child: const Text('Next'),
          ),
        ],
      ),
    );
  }
}

class _ClinicianIdStep extends StatelessWidget {
  const _ClinicianIdStep({
    required this.clinicianId,
    required this.onCopy,
    required this.onNext,
  });

  final String? clinicianId;
  final VoidCallback onCopy;
  final Future<void> Function() onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Your Clinician ID', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text('Your unique ID', style: theme.textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Patients use this ID when sending you encrypted reports.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F0EB),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE0DED7)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    clinicianId ?? 'Generating...',
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                IconButton(
                  onPressed: clinicianId == null ? null : onCopy,
                  icon: const Icon(Icons.copy_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'This ID does not identify you to the server. It is just a routing label for encrypted blobs.',
            style: theme.textTheme.bodySmall,
          ),
          const Spacer(),
          FilledButton(onPressed: onNext, child: const Text('Next')),
        ],
      ),
    );
  }
}

class _ReadyStep extends StatelessWidget {
  const _ReadyStep({required this.onFinish});

  final Future<void> Function() onFinish;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('You\'re ready', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 20),
          Icon(Icons.verified_rounded, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 14),
          _ReadyItem(text: 'Profile stored locally'),
          _ReadyItem(text: 'RSA keypair generated'),
          _ReadyItem(text: 'Clinician ID ready'),
          const Spacer(),
          FilledButton(
            onPressed: onFinish,
            child: const Text('Go to Dashboard'),
          ),
        ],
      ),
    );
  }
}

class _ReadyItem extends StatelessWidget {
  const _ReadyItem({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(Icons.check_rounded, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(text, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F0EB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0DED7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

String _uuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  String hex(int value) => value.toRadixString(16).padLeft(2, '0');

  final b = bytes.map(hex).toList(growable: false);
  return '${b[0]}${b[1]}${b[2]}${b[3]}-${b[4]}${b[5]}-${b[6]}${b[7]}-${b[8]}${b[9]}-${b[10]}${b[11]}${b[12]}${b[13]}${b[14]}${b[15]}';
}
