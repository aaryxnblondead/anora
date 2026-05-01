import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/clinician_state.dart';
import '../theme/anora_theme.dart';
import 'widgets/report_detail_sheet.dart';

class ReportsTab extends ConsumerWidget {
  const ReportsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(clinicianReportsProvider);
    final notifier = ref.read(clinicianReportsProvider.notifier);
    final layout = AnoraLayoutSpec.of(context);

    final inboxRecords = state.inboxRecords;
    final reportCount = state.records.length;
    final decrypted = state.records.where((record) => record.isDecrypted).length;
    final flagged = state.records.where((record) {
      final risk = record.riskFlagCounts;
      if (risk == null) return false;
      return risk.values.any((count) => count > 0);
    }).length;

    return Padding(
      padding: layout.screenPadding(top: layout.minorGap + 4, bottom: layout.bottomPadding - 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AnoraScreenHeader(
            title: 'Reports',
            subtitle: 'Tap any report or emergency alert to view its locked-box summary.',
          ),
          SizedBox(height: layout.sectionGap - 2),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  value: '$reportCount',
                  label: 'Reports',
                  icon: Icons.receipt_long_rounded,
                ),
              ),
              SizedBox(width: layout.minorGap - 2),
              Expanded(
                child: _StatCard(
                  value: '$decrypted',
                  label: 'Decrypted',
                  icon: Icons.lock_open_rounded,
                ),
              ),
              SizedBox(width: layout.minorGap - 2),
              Expanded(
                child: _StatCard(
                  value: '${state.unreadAlertCount}',
                  label: 'Unread alerts',
                  icon: Icons.notification_important_rounded,
                ),
              ),
            ],
          ),
          if (flagged > 0) ...[
            SizedBox(height: layout.minorGap - 2),
            AnoraSectionCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(
                '$flagged item${flagged == 1 ? '' : 's'} have risk flags.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          if (state.alerts.isNotEmpty) ...[
            SizedBox(height: layout.sectionGap),
            Text('Emergency inbox', style: Theme.of(context).textTheme.titleMedium),
          ],
          SizedBox(height: layout.sectionGap - 2),
          Expanded(
            child: inboxRecords.isEmpty
                ? Center(
                    child: AnoraSectionCard(
                      emphasis: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'No reports or alerts yet.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: inboxRecords.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final record = inboxRecords[index];
                      return _ReportListTile(record: record, notifier: notifier);
                    },
                  ),
          ),
          if (state.error != null)
            Text(
              state.error!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label, required this.icon});

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
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.primary),
          ),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ReportListTile extends StatelessWidget {
  const _ReportListTile({required this.record, required this.notifier});

  final PatientRecord record;
  final ClinicianReportsNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final isEmergencyAlert = record.isEmergencyAlert;
    final isMoodUpdate = record.isMoodUpdate;
    final score = record.avgMoodScore;
    final moodColor = _scoreColor(context, score);

    return AnoraSectionCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          if (isEmergencyAlert) {
            await notifier.markAlertRead(record.reportId);
          }
          if (!context.mounted) return;
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => ReportDetailSheet(record: record, notifier: notifier),
          );
        },
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: isEmergencyAlert
                ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.65)
                : Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
            foregroundColor: isEmergencyAlert
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary,
            child: Icon(
              isEmergencyAlert
                  ? Icons.warning_rounded
                  : isMoodUpdate
                  ? Icons.monitor_heart_rounded
                  : record.isDecrypted
                  ? Icons.lock_open_rounded
                  : Icons.lock_rounded,
            ),
          ),
          title: Text(record.patientLabel),
          subtitle: Text(
            isEmergencyAlert
                ? '${record.alertPriority ?? 'high'} priority · ${_formatDate(record.receivedAt)}'
                : isMoodUpdate
                ? 'Latest mood update · ${_formatDate(record.receivedAt)}'
                : _formatDate(record.receivedAt),
          ),
          trailing: isEmergencyAlert
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (record.isUnread)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.error,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Unread',
                          style: TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ),
                    if (record.isUnread) const SizedBox(height: 6),
                    Text(
                      'Alert',
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                )
              : record.isDecrypted && score != null
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: moodColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('${(score * 100).round()}%'),
                  ],
                )
              : null,
        ),
      ),
    );
  }

  Color _scoreColor(BuildContext context, double? score) {
    if (score == null) return const Color(0xFFE0DED7);
    if (score >= 0.62) return Theme.of(context).colorScheme.primary;
    if (score >= 0.40) return Theme.of(context).colorScheme.secondary;
    return Theme.of(context).colorScheme.error;
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
    final month = months[date.month - 1];
    return '$month ${date.day}, ${date.year}';
  }
}
