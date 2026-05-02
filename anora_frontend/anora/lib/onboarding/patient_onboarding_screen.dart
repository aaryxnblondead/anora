import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../services/phone_otp_auth_service.dart';
import '../services/secure_link_service.dart';
import '../services/storage_service.dart';
import '../theme/anora_theme.dart';

class PatientOnboardingScreen extends StatefulWidget {
  const PatientOnboardingScreen({super.key});

  @override
  State<PatientOnboardingScreen> createState() => _PatientOnboardingScreenState();
}

class _PatientOnboardingScreenState extends State<PatientOnboardingScreen> {
  final PageController _controller = PageController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  int _index = 0;
  bool _saving = false;
  bool _otpBusy = false;
  bool _otpSent = false;
  bool _phoneVerified = false;
  String? _challengeId;

  @override
  void initState() {
    super.initState();
    final session = PhoneOtpAuthService.instance.readSession();
    if (session != null && session.role == UserRole.patient && !session.isExpired) {
      _phoneController.text = session.phoneNumber;
      _phoneVerified = true;
      _otpSent = true;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (!_phoneVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verify your phone number with OTP to continue.')),
      );
      return;
    }
    await _controller.nextPage(
      duration: AnoraMotion.standard,
      curve: AnoraMotion.standardCurve,
    );
  }

  Future<void> _requestOtp() async {
    if (_otpBusy) return;
    setState(() => _otpBusy = true);
    try {
      final patientDeviceId = await SecureLinkService.instance.getOrCreatePatientDeviceId();
      final challengeId = await PhoneOtpAuthService.instance.requestOtp(
        phoneNumber: _phoneController.text,
        role: UserRole.patient,
        patientDeviceId: patientDeviceId,
      );
      if (!mounted) return;
      setState(() {
        _challengeId = challengeId;
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
        setState(() => _otpBusy = false);
      }
    }
  }

  Future<void> _verifyOtp() async {
    if (_otpBusy) return;
    final challengeId = _challengeId;
    if (challengeId == null || challengeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request OTP first.')),
      );
      return;
    }

    setState(() => _otpBusy = true);
    try {
      final session = await PhoneOtpAuthService.instance.verifyOtp(
        challengeId: challengeId,
        phoneNumber: _phoneController.text,
        otpCode: _otpController.text,
      );
      if (!mounted) return;
      if (session.role != UserRole.patient) {
        throw Exception('This phone is not registered as a patient account.');
      }
      setState(() => _phoneVerified = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone verified successfully.')),
      );
      await _next();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('OTP verification failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _otpBusy = false);
      }
    }
  }

  Future<void> _finish() async {
    if (_saving) return;
    final patientDeviceId = await SecureLinkService.instance.getOrCreatePatientDeviceId();
    if (!mounted) return;
    if (!_phoneVerified ||
        !PhoneOtpAuthService.instance.hasValidSessionForRole(
          UserRole.patient,
          patientDeviceId: patientDeviceId,
        )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complete phone OTP verification first.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await StorageService.instance.settingsBox.put('patient_onboarding_complete', true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not finish onboarding: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                    title: 'Patient Onboarding',
                    subtitle: 'Set up your private journaling space in under a minute.',
                  ),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _controller,
                  onPageChanged: (value) => setState(() => _index = value),
                  children: [
                    _OnboardingPage(
                      icon: _phoneVerified ? Icons.verified_user_rounded : Icons.sms_rounded,
                      title: 'Verify your phone with OTP',
                      body:
                          'Use your phone number in E.164 format (e.g. +15551234567). This gives you a real authenticated patient identity.',
                      actionLabel: _phoneVerified
                          ? 'Verified'
                          : (_otpSent ? (_otpBusy ? 'Verifying...' : 'Verify OTP') : (_otpBusy ? 'Sending OTP...' : 'Send OTP')),
                      onAction: _phoneVerified
                          ? _next
                          : (_otpSent ? _verifyOtp : _requestOtp),
                      child: Column(
                        children: [
                          TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Phone number',
                              hintText: '+15551234567',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _otpController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'OTP code',
                              hintText: _otpSent ? 'Enter 6-digit code' : 'Request code first',
                            ),
                          ),
                        ],
                      ),
                    ),
                    _OnboardingPage(
                      icon: Icons.favorite_border_rounded,
                      title: 'Your emotional companion',
                      body:
                          'Track your feelings with gentle check-ins, mood paths, and private insights that stay with you.',
                      actionLabel: _saving ? 'Finishing...' : 'Get Started',
                      onAction: _saving ? null : _finish,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.only(bottom: layout.bottomPadding - 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    2,
                    (dot) => AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: _index == dot ? 18 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: _index == dot
                            ? theme.colorScheme.primary
                            : AnoraPalette.border,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
    this.child,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback? onAction;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = AnoraLayoutSpec.of(context);
    return Padding(
      padding: layout.screenPadding(top: layout.minorGap, bottom: layout.bottomPadding - 2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Expanded(
            child: AnoraStaggeredReveal(
              order: 1,
              child: AnoraSectionCard(
                emphasis: true,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: layout.isCompact ? 78 : 88,
                      height: layout.isCompact ? 78 : 88,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: layout.isCompact ? 36 : 42, color: theme.colorScheme.primary),
                    ),
                    SizedBox(height: layout.sectionGap),
                    Text(
                      title,
                      style: theme.textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: layout.minorGap),
                    Text(
                      body,
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    if (child != null) ...[
                      SizedBox(height: layout.sectionGap),
                      child!,
                    ],
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: layout.sectionGap),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onAction,
              child: AnimatedSwitcher(
                duration: AnoraMotion.quick,
                switchInCurve: AnoraMotion.standardCurve,
                child: Text(actionLabel, key: ValueKey<String>(actionLabel)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
