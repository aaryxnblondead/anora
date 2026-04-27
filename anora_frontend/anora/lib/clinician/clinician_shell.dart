import 'dart:async';

import 'package:anora/services/report_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/clinician_state.dart';
import 'patient_feed_tab.dart';
import 'patient_list_tab.dart';
import 'profile_tab.dart';
import 'providers/linked_patients_provider.dart';

class ClinicianShell extends ConsumerStatefulWidget {
  const ClinicianShell({super.key, required this.clinicianId});

  final String clinicianId;

  @override
  ConsumerState<ClinicianShell> createState() => _ClinicianShellState();
}

class _ClinicianShellState extends ConsumerState<ClinicianShell>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  late final List<Widget> _tabs;
  Timer? _periodicSyncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _tabs = [
      const PatientListTab(),
      PatientFeedTab(clinicianId: widget.clinicianId),
      const ProfileTab(),
    ];

    unawaited(_syncInboxOnResume());
    _periodicSyncTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_syncInboxOnResume()),
    );
  }

  @override
  void dispose() {
    _periodicSyncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncInboxOnResume());
    }
  }

  Future<void> _syncInboxOnResume() async {
    await Future.wait([
      ref.read(linkedPatientsProvider.notifier).sync(),
      ref.read(clinicianReportsProvider.notifier).syncLatestReports(),
      ref.read(clinicianReportsProvider.notifier).syncEmergencyAlerts(),
      ref.read(clinicianReportsProvider.notifier).syncLatestMoodUpdates(),
    ]);
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _generateAndShowInviteCode() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final code =
          await ReportService.instance.generateInviteCode(widget.clinicianId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Patient Invite Code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Share this single-use code with your patient to establish a secure link. The code expires in 24 hours.',
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  code,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                messenger.showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard!')),
                );
              },
              child: const Text('Copy Code'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to generate code: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinician Portal'),
        actions: _selectedIndex == 0
            ? [
                IconButton(
                  icon: const Icon(Icons.person_add),
                  onPressed: _generateAndShowInviteCode,
                  tooltip: 'Generate Patient Invite Code',
                ),
              ]
            : null,
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _tabs,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Patients',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.feed),
            label: 'Updates',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
