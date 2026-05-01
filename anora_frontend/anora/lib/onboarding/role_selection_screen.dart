import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_role.dart';
import '../state/role_controller.dart';
import '../theme/anora_theme.dart';

class RoleSelectionScreen extends ConsumerStatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  ConsumerState<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends ConsumerState<RoleSelectionScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _firstOpacity;
  late final Animation<double> _secondOpacity;
  late final Animation<Offset> _firstOffset;
  late final Animation<Offset> _secondOffset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _firstOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.75, curve: Curves.easeOut),
    );
    _secondOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.25, 1.0, curve: Curves.easeOut),
    );

    _firstOffset = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _secondOffset = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.25, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _selectRole(UserRole role) async {
    await ref.read(roleProvider.notifier).setRole(role);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final layout = AnoraLayoutSpec.of(context);

    return AnoraBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: layout.screenPadding(bottom: layout.bottomPadding + 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnoraStaggeredReveal(
                  order: 0,
                  child: AnoraScreenHeader(
                    title: 'Welcome to Anora',
                    subtitle: layout.isCompact
                        ? 'Choose a role to tailor your experience.'
                        : 'Choose how you want to start so we can tailor your experience.',
                  ),
                ),
                SizedBox(height: layout.sectionGap),
                Expanded(
                  child: Column(
                    children: [
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (context, child) {
                          return Opacity(
                            opacity: _firstOpacity.value,
                            child: Transform.translate(
                              offset: Offset(0, _firstOffset.value.dy * 40),
                              child: child,
                            ),
                          );
                        },
                        child: _RoleCard(
                          icon: Icons.edit_note_rounded,
                          iconColor: colors.primary,
                          title: 'I\'m here to journal',
                          subtitle:
                              'Track your mood, write privately, and share safe summaries with care teams.',
                          onTap: () => _selectRole(UserRole.patient),
                        ),
                      ),
                      SizedBox(height: layout.sectionGap),
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (context, child) {
                          return Opacity(
                            opacity: _secondOpacity.value,
                            child: Transform.translate(
                              offset: Offset(0, _secondOffset.value.dy * 40),
                              child: child,
                            ),
                          );
                        },
                        child: _RoleCard(
                          icon: Icons.medical_services_rounded,
                          iconColor: colors.secondary,
                          title: 'I\'m a Clinician',
                          subtitle:
                              'Review encrypted patient trends and respond quickly to risk alerts.',
                          onTap: () => _selectRole(UserRole.clinician),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Your choice is stored only on this device.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = AnoraLayoutSpec.of(context);
    return AnoraSectionCard(
      emphasis: true,
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(layout.isCompact ? 14 : 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: layout.isCompact ? 42 : 46,
                  height: layout.isCompact ? 42 : 46,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, size: layout.isCompact ? 22 : 24, color: iconColor),
                ),
                SizedBox(width: layout.isCompact ? 10 : 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 6),
                      Text(subtitle, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
