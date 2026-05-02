import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/clinician_push_service.dart';
import '../state/clinician_state.dart';
import '../theme/anora_theme.dart';
import 'providers/linked_patients_provider.dart';

class PatientListTab extends ConsumerStatefulWidget {
  const PatientListTab({super.key});

  @override
  ConsumerState<PatientListTab> createState() => _PatientListTabState();
}

class _PatientListTabState extends ConsumerState<PatientListTab> {
  @override
  void initState() {
    super.initState();
    Future.microtask(_refreshAll);
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      ref.read(linkedPatientsProvider.notifier).sync(),
      ref.read(clinicianReportsProvider.notifier).syncLatestReports(),
      ref.read(clinicianReportsProvider.notifier).syncLatestMoodUpdates(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final linkedState = ref.watch(linkedPatientsProvider);
    final records = ref.watch(clinicianReportsProvider.select((s) => s.inboxRecords));
    final layout = AnoraLayoutSpec.of(context);

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: layout.maxReadableWidth),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: layout.screenPadding(
              top: layout.minorGap + 2,
              bottom: layout.bottomPadding,
            ),
            children: [
              const AnoraScreenHeader(
                title: 'Linked Patients',
                subtitle: 'Review each patient\'s latest encrypted update and mood signal at a glance.',
              ),
              SizedBox(height: layout.sectionGap),
              Row(
                children: [
                  Expanded(
                    child: _PatientMetricTile(
                      label: 'Active Patients',
                      value: '${linkedState.totalLinked}',
                      icon: Icons.groups_2_rounded,
                    ),
                  ),
                  SizedBox(width: layout.minorGap),
                  Expanded(
                    child: _PatientMetricTile(
                      label: 'Inbox Events',
                      value: '${records.length}',
                      icon: Icons.inbox_rounded,
                    ),
                  ),
                ],
              ),
              SizedBox(height: layout.sectionGap),
              if (linkedState.isLoading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(minHeight: 3),
                ),
              if (linkedState.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    linkedState.error!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                ),
              if (linkedState.patients.isEmpty && !linkedState.isLoading)
                const _EmptyPatientsState()
              else
                ...linkedState.patients.map(
                  (patient) => Padding(
                    padding: EdgeInsets.only(bottom: layout.minorGap),
                    child: _PatientSummaryCard(patient: patient),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PatientMetricTile extends StatelessWidget {
  const _PatientMetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnoraSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: theme.textTheme.titleLarge),
                Text(label, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPatientsState extends StatelessWidget {
  const _EmptyPatientsState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnoraSectionCard(
      emphasis: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          children: [
            Icon(Icons.group_add_rounded, size: 40, color: theme.colorScheme.primary),
            const SizedBox(height: 10),
            Text('No linked patients yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Use the + button to generate an invite code and connect with your first patient.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientSummaryCard extends StatelessWidget {
  const _PatientSummaryCard({required this.patient});

  final LinkedPatientEntry patient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topEmotion = patient.latestMood?.moodLabels.isNotEmpty == true
        ? patient.latestMood!.moodLabels.last
        : null;
    final moodValue = patient.latestMood?.moodScore.toStringAsFixed(1) ?? '--';

    return AnoraSectionCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => _LinkedPatientDetailSheet(patient: patient),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                  child: Text(
                    patient.patientLabel.isNotEmpty ? patient.patientLabel[0].toUpperCase() : '?',
                    style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              patient.patientLabel,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ID: ${patient.patientDeviceId}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _PatientInfoPill(label: 'Mood $moodValue'),
                          _PatientInfoPill(label: topEmotion?.trim().isNotEmpty == true ? topEmotion! : 'No emotion tag'),
                          _PatientInfoPill(label: _formatUpdated(patient.latestMood?.lastMoodAt ?? patient.linkedAt)),
                        ],
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

  String _formatUpdated(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1) return 'Updated just now';
    if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Updated ${diff.inHours}h ago';
    return 'Updated ${diff.inDays}d ago';
  }
}

class _PatientInfoPill extends StatelessWidget {
  const _PatientInfoPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: theme.textTheme.labelMedium),
    );
  }
}

class _LinkedPatientDetailSheet extends StatelessWidget {
  const _LinkedPatientDetailSheet({required this.patient});

  final LinkedPatientEntry patient;

  @override
  Widget build(BuildContext context) {
    final mood = patient.latestMood;
    final score = mood?.moodScore ?? 0.0;
    final trendPoints = patient.moodHistory.isNotEmpty
        ? patient.moodHistory
        : (mood != null ? <double>[mood.moodScore] : const <double>[]);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.84,
      maxChildSize: 0.95,
      minChildSize: 0.56,
      builder: (context, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF7F6F2),
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            children: [
              Text(patient.patientLabel, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text('Live mood update', style: Theme.of(context).textTheme.bodySmall),
              Text(_formatDate(mood?.lastMoodAt ?? patient.linkedAt), style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Mood Overview',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${(score * 100).round()}%',
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                            color: _scoreColor(context, score),
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      mood?.moodDescriptor ?? 'No mood data yet',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 14),
                    if (trendPoints.isNotEmpty)
                      SizedBox(
                        height: 150,
                        child: _MoodTrendChart(points: trendPoints),
                      )
                    else
                      Text(
                        'No trend data available yet.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Risk Flags',
                child: _RiskFlags(flags: mood?.riskFlags ?? const <String>[]),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Entry Activity',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Trend points: ${trendPoints.length}'),
                    const SizedBox(height: 6),
                    Text(
                      'Top emotion: ${mood?.moodLabels.isNotEmpty == true ? mood!.moodLabels.last : 'Not available'}',
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    const months = <String>[
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
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Color _scoreColor(BuildContext context, double score) {
    if (score >= 0.62) return Theme.of(context).colorScheme.primary;
    if (score >= 0.40) return Theme.of(context).colorScheme.secondary;
    return Theme.of(context).colorScheme.error;
  }
}

class _MoodTrendChart extends StatelessWidget {
  const _MoodTrendChart({required this.points});

  final List<double> points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final safePoints = points.map((p) => p.clamp(0.0, 1.0)).toList(growable: false);

    final chartPoints = <FlSpot>[];
    for (var i = 0; i < safePoints.length; i++) {
      chartPoints.add(FlSpot(i.toDouble(), safePoints[i]));
    }

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 1,
        minX: 0,
        maxX: (safePoints.length - 1).toDouble(),
        gridData: FlGridData(
          show: true,
          horizontalInterval: 0.25,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: theme.colorScheme.outline.withValues(alpha: 0.24),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        titlesData: const FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: chartPoints,
            isCurved: true,
            barWidth: 3,
            color: theme.colorScheme.primary,
            dotData: FlDotData(show: safePoints.length <= 2),
            belowBarData: BarAreaData(
              show: true,
              color: theme.colorScheme.primary.withValues(alpha: 0.16),
            ),
          ),
        ],
      ),
    );
  }
}

class _RiskFlags extends StatelessWidget {
  const _RiskFlags({required this.flags});

  final List<String> flags;

  @override
  Widget build(BuildContext context) {
    if (flags.isEmpty) {
      return Text(
        'No risk flags detected in this report period.',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: flags
          .map(
            (flag) => Chip(
              label: Text(flag),
              avatar: Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F0EB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0DED7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
