import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'patients_tab.dart';
import 'profile_tab.dart';
import 'reports_tab.dart';
import '../state/clinician_state.dart';

class ClinicianShell extends ConsumerStatefulWidget {
  const ClinicianShell({super.key});

  @override
  ConsumerState<ClinicianShell> createState() => _ClinicianShellState();
}

class _ClinicianShellState extends ConsumerState<ClinicianShell>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  late final PageController _pageController;
  Timer? _syncTimer;

  final List<_ClinicianNavTab> _tabs = const [
    _ClinicianNavTab(label: 'Patients', icon: Icons.people_rounded),
    _ClinicianNavTab(label: 'Reports', icon: Icons.folder_open_rounded),
    _ClinicianNavTab(label: 'Profile', icon: Icons.person_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    WidgetsBinding.instance.addObserver(this);
    _syncInboxOnResume();
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _syncInboxOnResume();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncInboxOnResume();
    }
  }

  Future<void> _syncInboxOnResume() async {
    final notifier = ref.read(clinicianReportsProvider.notifier);
    await notifier.syncEmergencyAlerts();
    await notifier.syncLatestReports();
    await notifier.syncLatestMoodUpdates();
  }

  void _jumpTo(int index) {
    if (_currentIndex == index) return;
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(clinicianReportsProvider);
    return Scaffold(
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          onPageChanged: (index) => setState(() => _currentIndex = index),
          children: const [
            PatientsTab(),
            ReportsTab(),
            ProfileTab(),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _jumpTo,
        items: _tabs
            .map(
              (tab) => BottomNavigationBarItem(
                icon: _TabIcon(
                  icon: tab.icon,
                  unreadCount: tab.label == 'Reports' ? state.unreadAlertCount : 0,
                ),
                label: tab.label,
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _TabIcon extends StatelessWidget {
  const _TabIcon({required this.icon, required this.unreadCount});

  final IconData icon;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (unreadCount > 0)
          Positioned(
            right: -8,
            top: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                borderRadius: BorderRadius.circular(999),
              ),
              constraints: const BoxConstraints(minWidth: 18),
              child: Text(
                unreadCount > 9 ? '9+' : '$unreadCount',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontSize: 10,
                      height: 1.0,
                    ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ClinicianNavTab {
  const _ClinicianNavTab({required this.label, required this.icon});

  final String label;
  final IconData icon;
}
