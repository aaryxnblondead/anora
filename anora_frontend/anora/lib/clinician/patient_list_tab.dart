import 'package:anora/state/clinician_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final notifier = ref.read(clinicianReportsProvider.notifier);

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(clinicianReportsProvider.notifier).syncLatestReports();
        await ref.read(clinicianReportsProvider.notifier).syncLatestMoodUpdates();
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (patients.isEmpty && !isLoading)
            const Text('No linked patients yet.\nUse the + button to generate an invite code.', textAlign: TextAlign.center),
          ListView.builder(
            itemCount: patients.length,
            itemBuilder: (context, index) {
              final patient = patients[index];
              return ListTile(
                leading: CircleAvatar(child: Text(patient.patientLabel.isNotEmpty ? patient.patientLabel[0] : '?')),
                title: Text(patient.patientLabel),
                subtitle: Text('ID: ${patient.patientDeviceId ?? "Unknown"}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => ReportDetailSheet(record: patient, notifier: notifier),
                  );
                },
              );
            },
          ),
          if (isLoading && patients.isEmpty) const CircularProgressIndicator(),
        ],
      ),
    );
  }
}