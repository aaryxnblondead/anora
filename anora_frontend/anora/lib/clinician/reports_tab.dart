import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/clinician_state.dart';
import 'widgets/report_detail_sheet.dart';

class ReportsTab extends ConsumerWidget {
  const ReportsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(clinicianReportsProvider);
    final notifier = ref.read(clinicianReportsProvider.notifier);

    final records = [...state.records]..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    final total = records.length;
    final decrypted = records.where((record) => record.isDecrypted).length;
    final flagged = records.where((record) {
      final risk = record.riskFlagCounts;
      if (risk == null) return false;
      return risk.values.any((count) => count > 0);
    }).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reports', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(
            'Tap any report to view its decrypted summary.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _StatCard(value: '$total', label: 'Total reports')),
              const SizedBox(width: 8),
              Expanded(child: _StatCard(value: '$decrypted', label: 'Decrypted')),
              const SizedBox(width: 8),
              Expanded(child: _StatCard(value: '$flagged', label: 'Flagged')),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: records.isEmpty
                ? Center(
                    child: Text(
                      'No reports yet.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView.separated(
                    itemCount: records.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final record = records[index];
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
  const _StatCard({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0DED7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
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
    final score = record.avgMoodScore;
    final moodColor = _scoreColor(context, score);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => ReportDetailSheet(record: record, notifier: notifier),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE0DED7)),
          ),
          child: ListTile(
            leading: Icon(
              record.isDecrypted ? Icons.lock_open_rounded : Icons.lock_rounded,
              color: record.isDecrypted
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.secondary,
            ),
            title: Text(record.patientLabel),
            subtitle: Text(_formatDate(record.receivedAt)),
            trailing: record.isDecrypted && score != null
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
