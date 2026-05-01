import 'dart:async';

import 'package:anora/services/report_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/clinician_state.dart';
import '../theme/anora_theme.dart';
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
  late final PageController _pageController;
  Timer? _periodicSyncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController();

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
    _pageController.dispose();
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
    final previousCount = ref.read(clinicianReportsProvider).alerts.length;
    await Future.wait([
      ref.read(linkedPatientsProvider.notifier).sync(),
      ref.read(clinicianReportsProvider.notifier).syncLatestReports(),
      ref.read(clinicianReportsProvider.notifier).syncEmergencyAlerts(),
      ref.read(clinicianReportsProvider.notifier).syncLatestMoodUpdates(),
    ]);
    final currentState = ref.read(clinicianReportsProvider);
    if (mounted && currentState.alerts.length > previousCount && currentState.alerts.isNotEmpty) {
      final newest = currentState.alerts.first;
      if (newest.isEmergencyAlert) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('New risk alert from ${newest.patientLabel}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _onItemTapped(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
    _pageController.animateToPage(
      index,
      duration: AnoraMotion.standard,
      curve: AnoraMotion.standardCurve,
    );
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
    final unreadAlerts = ref.watch(clinicianReportsProvider.select((s) => s.unreadAlertCount));

    return AnoraBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Clinician Portal'),
          actions: [
            if (unreadAlerts > 0)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$unreadAlerts alert${unreadAlerts == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.onError,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ),
              ),
            if (_selectedIndex == 0)
              IconButton(
                icon: const Icon(Icons.person_add_rounded),
                onPressed: _generateAndShowInviteCode,
                tooltip: 'Generate Patient Invite Code',
              ),
          ],
        ),
        body: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          onPageChanged: (index) => setState(() => _selectedIndex = index),
          children: _tabs,
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _onItemTapped,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.groups_rounded),
              selectedIcon: Icon(Icons.groups_2_rounded),
              label: 'Patients',
            ),
            NavigationDestination(
              icon: Icon(Icons.monitor_heart_outlined),
              selectedIcon: Icon(Icons.monitor_heart_rounded),
              label: 'Updates',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
