import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../clinician/clinician_shell.dart';
import '../models/user_role.dart';
import '../services/clinician_crypto_service.dart';
import '../services/phone_otp_auth_service.dart';
import '../services/secure_link_service.dart';
import '../services/storage_service.dart';
import '../theme/anora_theme.dart';

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
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  final Map<String, String> _formData = <String, String>{};

  int _pageIndex = 0;
  bool _isBusy = false;
  bool _showImportField = false;
  String? _publicKeyPem;
  String? _clinicianId;
  String? _otpChallengeId;
  bool _otpSent = false;
  bool _phoneVerified = false;

  @override
  void initState() {
    super.initState();
    final box = StorageService.instance.settingsBox;
    _nameController.text = (box.get('clinician_name') as String?) ?? '';
    _credentialsController.text = (box.get('clinician_credentials') as String?) ?? '';
    _publicKeyPem = ClinicianCryptoService.instance.getPublicKeyPem();

    final session = PhoneOtpAuthService.instance.readSession();
    if (session != null && session.role == UserRole.clinician && !session.isExpired) {
      _phoneController.text = session.phoneNumber;
      _phoneVerified = true;
      _otpSent = true;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _credentialsController.dispose();
    _importPrivateKeyController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _nextPage() async {
    await _pageController.nextPage(
      duration: AnoraMotion.standard,
      curve: AnoraMotion.standardCurve,
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
        const SnackBar(content: Text('Private connection credentials prepared.')),
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
        const SnackBar(content: Text('Connection credentials imported successfully.')),
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

  Future<void> _requestOtp() async {
    if (_isBusy) return;
    final clinicianId = _clinicianId;
    if (clinicianId == null || clinicianId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clinician ID is not ready yet.')),
      );
      return;
    }

    setState(() => _isBusy = true);
    try {
      final challengeId = await PhoneOtpAuthService.instance.requestOtp(
        phoneNumber: _phoneController.text,
        role: UserRole.clinician,
        clinicianId: clinicianId,
      );
      if (!mounted) return;
      setState(() {
        _otpChallengeId = challengeId;
        _otpSent = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OTP sent to your phone.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send OTP: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _verifyOtp() async {
    if (_isBusy) return;
    final challengeId = _otpChallengeId;
    if (challengeId == null || challengeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request OTP first.')),
      );
      return;
    }

    setState(() => _isBusy = true);
    try {
      final session = await PhoneOtpAuthService.instance.verifyOtp(
        challengeId: challengeId,
        phoneNumber: _phoneController.text,
        otpCode: _otpController.text,
      );
      if (!mounted) return;
      if (session.role != UserRole.clinician) {
        throw Exception('This phone is not registered as a clinician account.');
      }
      final clinicianId = _clinicianId;
      if (clinicianId != null && clinicianId.isNotEmpty && session.clinicianId != clinicianId) {
        throw Exception('Authenticated clinician identity does not match this clinician ID.');
      }

      setState(() => _phoneVerified = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone verified successfully.')),
      );
      await _nextPage();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('OTP verification failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _completeOnboarding() async {
    try {
      final clinicianId = (_clinicianId ?? '').trim();
      if (clinicianId.isEmpty) {
        throw Exception('Clinician ID is missing.');
      }

      if (!_phoneVerified ||
          !PhoneOtpAuthService.instance.hasValidSessionForRole(
            UserRole.clinician,
            clinicianId: clinicianId,
          )) {
        throw Exception('Complete phone OTP verification before continuing.');
      }

      final publicKeyPem = _publicKeyPem;
      if (publicKeyPem != null) {
        try {
          await SecureLinkService.instance.registerClinicianConnection(
            clinicianId: clinicianId,
            publicKeyPem: publicKeyPem,
          );
        } catch (_) {
          // Keep onboarding non-blocking if backend registration is temporarily unavailable.
        }

        await SecureLinkService.instance.ensureClinicianSessionToken(
          clinicianId: clinicianId,
        );
      }
      await StorageService.instance.settingsBox.put('clinician_onboarding_complete', true);

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => ClinicianShell(clinicianId: clinicianId),
        ),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not complete onboarding: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = AnoraLayoutSpec.of(context);

    return AnoraBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: layout.screenPadding(top: layout.topPadding, bottom: layout.minorGap),
                child: const AnoraStaggeredReveal(
                  order: 0,
                  child: AnoraScreenHeader(
                    title: 'Clinician Onboarding',
                    subtitle: 'Set up secure keys, claim your clinician ID, and access the dashboard.',
                  ),
                ),
              ),
              _StepDots(currentIndex: _pageIndex),
              SizedBox(height: layout.minorGap + 2),
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
                        final messenger = ScaffoldMessenger.of(context);
                        final id = _clinicianId;
                        if (id == null || id.isEmpty) return;
                        await Clipboard.setData(ClipboardData(text: id));
                        if (!mounted) return;
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Clinician ID copied.')),
                        );
                      },
                      onNext: _nextPage,
                    ),
                    _PhoneOtpStep(
                      phoneController: _phoneController,
                      otpController: _otpController,
                      isBusy: _isBusy,
                      otpSent: _otpSent,
                      phoneVerified: _phoneVerified,
                      onRequestOtp: _requestOtp,
                      onVerifyOtp: _verifyOtp,
                      onNext: _nextPage,
                    ),
                    _ReadyStep(onFinish: _completeOnboarding),
                  ],
                ),
              ),
            ],
          ),
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
    final layout = AnoraLayoutSpec.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        5,
        (index) => AnimatedContainer(
          duration: AnoraMotion.quick,
          width: currentIndex == index ? (layout.isCompact ? 16 : 18) : 8,
          height: 8,
          margin: EdgeInsets.symmetric(horizontal: layout.isCompact ? 3 : 4),
          decoration: BoxDecoration(
            color: currentIndex == index ? theme.colorScheme.primary : AnoraPalette.border,
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
    final layout = AnoraLayoutSpec.of(context);
    return Padding(
      padding: layout.screenPadding(top: layout.minorGap, bottom: layout.bottomPadding - 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AnoraScreenHeader(
            title: 'Your Identity',
            subtitle: 'Store your professional details locally on this device.',
          ),
          SizedBox(height: layout.sectionGap),
          AnoraSectionCard(
            child: Column(
              children: [
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
              ],
            ),
          ),
          SizedBox(height: layout.minorGap),
          Text(
            'Stored locally only. Never sent to any server.',
            style: Theme.of(context).textTheme.bodySmall,
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
    final layout = AnoraLayoutSpec.of(context);
    return Padding(
      padding: layout.screenPadding(top: layout.minorGap, bottom: layout.bottomPadding - 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AnoraScreenHeader(
            title: 'Private Connection Setup',
            subtitle: 'Prepare encrypted sharing credentials for patient reports.',
          ),
          SizedBox(height: layout.sectionGap),
          _OptionCard(
            title: 'Generate on device',
            child: FilledButton(
              onPressed: isBusy ? null : onGenerate,
              child: Text(isBusy ? 'Working...' : 'Prepare Private Connection'),
            ),
          ),
          SizedBox(height: layout.minorGap + 2),
          _OptionCard(
            title: 'Import recovery credentials',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton(
                  onPressed: isBusy ? null : onImportToggle,
                  child: const Text('Import Recovery File'),
                ),
                if (showImportField) ...[
                  SizedBox(height: layout.minorGap),
                  TextField(
                    controller: importController,
                    minLines: 8,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      hintText: 'Paste recovery credentials here',
                    ),
                  ),
                  SizedBox(height: layout.minorGap),
                  FilledButton.tonal(
                    onPressed: isBusy ? null : onImport,
                    child: const Text('Validate and Save'),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: layout.minorGap + 2),
          if (publicKeyPem != null && publicKeyPem!.isNotEmpty)
            AnoraSectionCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Private connection is ready.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Patients can now securely link using your Clinician ID.',
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
    final layout = AnoraLayoutSpec.of(context);
    return Padding(
      padding: layout.screenPadding(top: layout.minorGap, bottom: layout.bottomPadding - 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AnoraScreenHeader(
            title: 'Your Clinician ID',
            subtitle: 'Patients use this unique ID to securely link with your dashboard.',
          ),
          SizedBox(height: layout.sectionGap),
          AnoraSectionCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    clinicianId ?? 'Generating...',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                IconButton(
                  onPressed: clinicianId == null ? null : onCopy,
                  icon: const Icon(Icons.copy_rounded),
                ),
              ],
            ),
          ),
          SizedBox(height: layout.minorGap),
          Text(
            'This ID helps route private updates to your dashboard.',
            style: theme.textTheme.bodySmall,
          ),
          const Spacer(),
          FilledButton(onPressed: onNext, child: const Text('Next')),
        ],
      ),
    );
  }
}

class _PhoneOtpStep extends StatelessWidget {
  const _PhoneOtpStep({
    required this.phoneController,
    required this.otpController,
    required this.isBusy,
    required this.otpSent,
    required this.phoneVerified,
    required this.onRequestOtp,
    required this.onVerifyOtp,
    required this.onNext,
  });

  final TextEditingController phoneController;
  final TextEditingController otpController;
  final bool isBusy;
  final bool otpSent;
  final bool phoneVerified;
  final Future<void> Function() onRequestOtp;
  final Future<void> Function() onVerifyOtp;
  final Future<void> Function() onNext;

  @override
  Widget build(BuildContext context) {
    final layout = AnoraLayoutSpec.of(context);
    return Padding(
      padding: layout.screenPadding(top: layout.minorGap, bottom: layout.bottomPadding - 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AnoraScreenHeader(
            title: 'Phone Verification',
            subtitle: 'Authenticate your clinician account with phone OTP using AWS SMS.',
          ),
          SizedBox(height: layout.sectionGap),
          AnoraSectionCard(
            child: Column(
              children: [
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone number',
                    hintText: '+15551234567',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: otpController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'OTP code',
                    hintText: otpSent ? 'Enter 6-digit code' : 'Request OTP first',
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isBusy ? null : onRequestOtp,
                        child: Text(isBusy && !otpSent ? 'Sending...' : 'Send OTP'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: (isBusy || !otpSent) ? null : onVerifyOtp,
                        child: Text(isBusy && otpSent ? 'Verifying...' : 'Verify OTP'),
                      ),
                    ),
                  ],
                ),
                if (phoneVerified) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: const [
                      Icon(Icons.check_circle_rounded, color: Colors.green),
                      SizedBox(width: 8),
                      Expanded(child: Text('Phone verified successfully.')),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const Spacer(),
          FilledButton(
            onPressed: phoneVerified ? onNext : null,
            child: const Text('Next'),
          ),
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
    final layout = AnoraLayoutSpec.of(context);
    return Padding(
      padding: layout.screenPadding(top: layout.minorGap, bottom: layout.bottomPadding - 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AnoraScreenHeader(
            title: 'You\'re ready',
            subtitle: 'Your clinician workspace is configured and ready for secure care collaboration.',
          ),
          SizedBox(height: layout.sectionGap + 2),
          AnoraSectionCard(
            emphasis: true,
            child: Column(
              children: [
                Icon(Icons.verified_rounded, size: 64, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 14),
                _ReadyItem(text: 'Profile stored locally'),
                _ReadyItem(text: 'Private connection prepared'),
                _ReadyItem(text: 'Clinician ID ready'),
                _ReadyItem(text: 'Phone OTP verified'),
              ],
            ),
          ),
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
    return AnoraSectionCard(
      padding: const EdgeInsets.all(12),
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
