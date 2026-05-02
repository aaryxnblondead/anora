import 'package:flutter/material.dart';

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
  int _index = 0;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    await _controller.nextPage(
      duration: AnoraMotion.standard,
      curve: AnoraMotion.standardCurve,
    );
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await SecureLinkService.instance.getOrCreatePatientDeviceId();
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
                      icon: Icons.groups_rounded,
                      title: 'Connect with your clinician',
                      body:
                          'Create your private patient profile and link with your clinician using the invite code flow in the app.',
                      actionLabel: 'Continue',
                      onAction: _next,
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
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback? onAction;

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
