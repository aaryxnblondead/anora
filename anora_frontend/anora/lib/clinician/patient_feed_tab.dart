import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/clinician_push_service.dart';
import '../theme/anora_theme.dart';
import 'providers/linked_patients_provider.dart';

class PatientFeedTab extends ConsumerStatefulWidget {
  const PatientFeedTab({super.key, required this.clinicianId});

  final String clinicianId;

  @override
  ConsumerState<PatientFeedTab> createState() => _PatientFeedTabState();
}

class _PatientFeedTabState extends ConsumerState<PatientFeedTab> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(linkedPatientsProvider.notifier).sync();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(linkedPatientsProvider);
    final layout = AnoraLayoutSpec.of(context);

    if (state.isLoading && state.patients.isEmpty) {
      return Padding(
        padding: layout.screenPadding(top: layout.topPadding, bottom: layout.bottomPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const [
            AnoraScreenHeader(
              title: 'Live Feed',
              subtitle: 'Pulling encrypted patient updates...',
            ),
            SizedBox(height: 16),
            LinearProgressIndicator(minHeight: 3),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(linkedPatientsProvider.notifier).sync(),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: layout.maxReadableWidth),
          child: ListView(
            padding: layout.screenPadding(top: layout.topPadding, bottom: layout.bottomPadding),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: AnoraScreenHeader(
                      title: 'Live Feed',
                      subtitle: 'Linked patients and mood activity in real time.',
                    ),
                  ),
                  IconButton(
                    onPressed: () => ref.read(linkedPatientsProvider.notifier).sync(),
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Refresh',
                  ),
                ],
              ),
              SizedBox(height: layout.minorGap),
              Row(
                children: [
                  Expanded(
                    child: _StatBox(
                      value: '${state.totalLinked}',
                      label: 'Linked',
                      icon: Icons.groups_2_rounded,
                    ),
                  ),
                  SizedBox(width: layout.minorGap - 2),
                  Expanded(
                    child: _StatBox(
                      value: '${state.withMoodData}',
                      label: 'With mood data',
                      icon: Icons.bar_chart_rounded,
                    ),
                  ),
                  SizedBox(width: layout.minorGap - 2),
                  Expanded(
                    child: _StatBox(
                      value: '${state.withRiskFlags}',
                      label: 'Risk flags',
                      icon: Icons.warning_amber_rounded,
                    ),
                  ),
                ],
              ),
              SizedBox(height: layout.minorGap),
              Text(
                state.lastSyncAt == null
                    ? 'Last synced: never'
                    : 'Last synced: ${_relativeTime(state.lastSyncAt!.toLocal())}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              SizedBox(height: layout.sectionGap),
              if (state.patients.isEmpty)
                const _EmptyState()
              else
                ...state.patients.map((patient) => _PatientCard(patient: patient)),
              if (state.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  state.error!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnoraSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 8),
          Text(value, style: theme.textTheme.titleLarge),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _PatientCard extends ConsumerWidget {
  const _PatientCard({required this.patient});

  final LinkedPatientEntry patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mood = patient.latestMood;
    final hasRisk = mood?.hasRiskFlags == true;
    final moodScore = mood?.moodScore;
    final trendPoints = patient.moodHistory.isNotEmpty
        ? patient.moodHistory
        : (moodScore != null ? <double>[moodScore] : const <double>[]);

    Color? accent;
    if (hasRisk) {
      accent = theme.colorScheme.error;
    } else if (moodScore != null && moodScore >= 0.62) {
      accent = theme.colorScheme.primary;
    } else if (moodScore != null && moodScore >= 0.40) {
      accent = theme.colorScheme.secondary;
    }

    final labels = mood?.moodLabels ?? const <String>[];
    final flags = mood?.riskFlags ?? const <String>[];
    final relative = _relativeTime((mood?.lastMoodAt ?? patient.linkedAt).toLocal());

    final trimmed = patient.patientLabel.trim();
    final initials = trimmed.isEmpty
        ? 'PA'
        : trimmed.substring(0, trimmed.length >= 2 ? 2 : 1).toUpperCase();

    final moodColor = hasRisk
        ? theme.colorScheme.error
        : (moodScore != null && moodScore >= 0.62)
            ? theme.colorScheme.primary
            : theme.colorScheme.secondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnoraSectionCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onLongPress: () => _showRenameDialog(context, ref, patient),
          child: Container(
            decoration: BoxDecoration(
              border: accent == null
                  ? null
                  : Border(left: BorderSide(color: accent, width: 3.5)),
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                  child: Text(
                    initials,
                    style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(patient.patientLabel, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      if (labels.isNotEmpty)
                        Text(labels.join(' · '))
                      else
                        Text(
                          'No mood data yet',
                          style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                        ),
                      if (flags.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: flags
                              .map(
                                (flag) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.errorContainer.withValues(alpha: 0.95),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    flag,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onErrorContainer,
                                    ),
                                  ),
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(relative, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 102,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (patient.hasMoodData)
                        Text(
                          '${((mood?.moodScore ?? 0) * 100).round()}%',
                          style: TextStyle(
                            color: moodColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        )
                      else
                        Text('No data', style: theme.textTheme.bodySmall),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 30,
                        child: _MoodSparkline(
                          points: trendPoints,
                          color: moodColor,
                        ),
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

class _MoodSparkline extends StatelessWidget {
  const _MoodSparkline({required this.points, required this.color});

  final List<double> points;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final sanitizedPoints = points.isEmpty ? const <double>[0.5] : points;
    return CustomPaint(
      size: const Size(double.infinity, 30),
      painter: _MoodSparklinePainter(
        points: sanitizedPoints,
        color: sanitizedPoints.length == 1 ? const Color(0xFFC9CEC6) : color,
      ),
    );
  }
}

class _MoodSparklinePainter extends CustomPainter {
  const _MoodSparklinePainter({required this.points, required this.color});

  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final stepX = points.length == 1 ? 0.0 : size.width / (points.length - 1);
    const verticalPadding = 3.0;
    final availableHeight = size.height - verticalPadding * 2;

    for (var index = 0; index < points.length; index++) {
      final x = stepX * index;
      final y = verticalPadding + (1 - points[index].clamp(0.0, 1.0)) * availableHeight;
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MoodSparklinePainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.color != color;
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnoraSectionCard(
      emphasis: true,
      child: SizedBox(
        height: 280,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_add_rounded,
                size: 52,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text('No linked patients yet', style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Share your Clinician ID from the Profile tab.\n'
                'Patients link from the app Settings screen.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _relativeTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hours ago';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[dt.month - 1]} ${dt.day}';
}

Future<void> _showRenameDialog(
  BuildContext context,
  WidgetRef ref,
  LinkedPatientEntry patient,
) async {
  final ctrl = TextEditingController(text: patient.patientLabel);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Rename patient'),
      content: TextField(
        controller: ctrl,
        decoration: const InputDecoration(labelText: 'Label'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  ctrl.dispose();

  if (result != null && result.trim().isNotEmpty) {
    await ref
        .read(linkedPatientsProvider.notifier)
        .updatePatientLabel(patient.patientDeviceId, result);
  }
}