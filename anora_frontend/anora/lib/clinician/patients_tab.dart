import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/clinician_state.dart';
import 'widgets/report_detail_sheet.dart';

class PatientsTab extends ConsumerWidget {
  const PatientsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(clinicianReportsProvider);
    final notifier = ref.read(clinicianReportsProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Patients',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              IconButton(
                onPressed: () => _showAddReportDialog(context, notifier),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (state.records.isEmpty)
            Expanded(
              child: Center(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F0EB),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE0DED7)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.people_outline_rounded,
                        size: 40,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'No patient reports yet',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Ask your patients to share an encrypted report using your Clinician ID.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: state.records.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final record = state.records[index];
                  return _PatientCard(record: record, notifier: notifier);
                },
              ),
            ),
          if (state.error != null) ...[
            const SizedBox(height: 8),
            Text(
              state.error!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showAddReportDialog(
    BuildContext context,
    ClinicianReportsNotifier notifier,
  ) async {
    final controller = TextEditingController();
    var loading = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 22,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fetch a patient report',
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(labelText: 'Report ID'),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: loading
                          ? null
                          : () async {
                              setSheetState(() => loading = true);
                              try {
                                await notifier.fetchReport(controller.text.trim());
                                if (!sheetContext.mounted) return;
                                Navigator.of(sheetContext).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Report fetched.')),
                                );
                              } catch (error) {
                                if (!sheetContext.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Could not fetch report: $error')),
                                );
                              } finally {
                                if (sheetContext.mounted) {
                                  setSheetState(() => loading = false);
                                }
                              }
                            },
                      child: Text(loading ? 'Fetching...' : 'Fetch Report'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    controller.dispose();
  }
}

class _PatientCard extends StatelessWidget {
  const _PatientCard({required this.record, required this.notifier});

  final PatientRecord record;
  final ClinicianReportsNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final riskMap = record.riskFlagCounts ?? const <String, int>{};

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => ReportDetailSheet(record: record, notifier: notifier),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0DED7)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFFF1F0EB),
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              child: Text(_initials(record.patientLabel)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(record.patientLabel, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    record.isMoodUpdate
                        ? 'Latest mood update'
                        : 'Report ID: ${_shortReportId(record.reportId)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (record.isMoodUpdate && record.avgMoodScore != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Mood score ${(record.avgMoodScore! * 100).round()}%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (record.isDecrypted && riskMap.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: riskMap.entries
                          .where((entry) => entry.value > 0)
                          .map((entry) => _RiskChip(flag: entry.key, count: entry.value))
                          .toList(growable: false),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!record.isDecrypted)
              OutlinedButton(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) {
                      return AlertDialog(
                        title: const Text('Confirm patient consent'),
                        content: const Text(
                          'Confirm that patient consent is recorded before decrypting this report.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(dialogContext).pop(true),
                            child: const Text('Confirm'),
                          ),
                        ],
                      );
                    },
                  );
                  if (confirmed != true) {
                    return;
                  }

                  try {
                    await notifier.decryptRecord(
                      record.reportId,
                      consentGranted: true,
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Report decrypted.')),
                    );
                  } catch (error) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Decrypt failed: $error')),
                    );
                  }
                },
                child: const Text('Decrypt'),
              )
            else
              Icon(
                Icons.check_circle_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }

  String _shortReportId(String reportId) {
    if (reportId.length <= 8) return reportId;
    return '${reportId.substring(0, 8)}...';
  }

  String _initials(String label) {
    final parts = label.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'P';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
  }
}

class _RiskChip extends StatelessWidget {
  const _RiskChip({required this.flag, required this.count});

  final String flag;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = count > 2
        ? Theme.of(context).colorScheme.error
        : (count >= 1 ? Theme.of(context).colorScheme.secondary : const Color(0xFFE0DED7));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
        color: color.withValues(alpha: 0.14),
      ),
      child: Text(
        '$flag $count',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
