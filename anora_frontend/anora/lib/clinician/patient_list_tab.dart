import 'package:anora/state/clinician_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/anora_theme.dart';
import 'widgets/report_detail_sheet.dart';

// A provider to get a unique list of patients from all records.
final uniquePatientsProvider = Provider.autoDispose<List<PatientRecord>>((ref) {
  // Watch the combined list of records and alerts, sorted by date.
  final records = ref.watch(clinicianReportsProvider.select((s) => s.inboxRecords));
  final uniquePatientMap = <String, PatientRecord>{};

  // Since inboxRecords is sorted with the most recent first, the first time we see
  // a patientDeviceId, it's their most recent record.
  for (final record in records) {
    final deviceId = record.patientDeviceId;
    if (deviceId != null && deviceId.isNotEmpty) {
      if (!uniquePatientMap.containsKey(deviceId)) {
        uniquePatientMap[deviceId] = record;
      }
    }
  }
  // Return the list of unique patients, sorted alphabetically by label.
  final patientList = uniquePatientMap.values.toList();
  patientList.sort((a, b) => a.patientLabel.compareTo(b.patientLabel));
  return patientList;
});

class PatientListTab extends ConsumerStatefulWidget {
  const PatientListTab({super.key});

  @override
  ConsumerState<PatientListTab> createState() => _PatientListTabState();
}

class _PatientListTabState extends ConsumerState<PatientListTab> {
  @override
  void initState() {
    super.initState();
    // Fetch latest data when the tab is first initialized.
    Future.microtask(() {
      ref.read(clinicianReportsProvider.notifier).syncLatestReports();
      ref.read(clinicianReportsProvider.notifier).syncLatestMoodUpdates();
    });
  }

  @override
  Widget build(BuildContext context) {
    final patients = ref.watch(uniquePatientsProvider);
    final isLoading = ref.watch(clinicianReportsProvider.select((s) => s.isLoading));
    final records = ref.watch(clinicianReportsProvider.select((s) => s.inboxRecords));
    final notifier = ref.read(clinicianReportsProvider.notifier);
    final layout = AnoraLayoutSpec.of(context);

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(clinicianReportsProvider.notifier).syncLatestReports();
        await ref.read(clinicianReportsProvider.notifier).syncLatestMoodUpdates();
      },
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
                      value: '${patients.length}',
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
              if (isLoading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(minHeight: 3),
                ),
              if (patients.isEmpty && !isLoading)
                const _EmptyPatientsState()
              else
                ...patients.map(
                  (patient) => Padding(
                    padding: EdgeInsets.only(bottom: layout.minorGap),
                    child: _PatientSummaryCard(
                      patient: patient,
                      notifier: notifier,
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
  const _PatientSummaryCard({required this.patient, required this.notifier});

  final PatientRecord patient;
  final ClinicianReportsNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topEmotion = patient.topEmotion?.trim();
    final moodValue = patient.avgMoodScore?.toStringAsFixed(1) ?? '--';

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
              builder: (_) => ReportDetailSheet(record: patient, notifier: notifier),
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
                        'ID: ${patient.patientDeviceId ?? "Unknown"}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _PatientInfoPill(label: 'Mood $moodValue'),
                          _PatientInfoPill(label: topEmotion?.isNotEmpty == true ? topEmotion! : 'No emotion tag'),
                          _PatientInfoPill(label: _formatUpdated(patient.receivedAt)),
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