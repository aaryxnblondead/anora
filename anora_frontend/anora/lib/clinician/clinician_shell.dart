import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'patients_tab.dart';
import 'profile_tab.dart';
import 'reports_tab.dart';
import '../services/clinician_push_service.dart';

class ClinicianShell extends StatefulWidget {
  const ClinicianShell({super.key});

  @override
  State<ClinicianShell> createState() => _ClinicianShellState();
}

class _ClinicianShellState extends State<ClinicianShell> {
  int _currentIndex = 0;
  late final PageController _pageController;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;

  final List<_ClinicianNavTab> _tabs = const [
    _ClinicianNavTab(label: 'Patients', icon: Icons.people_rounded),
    _ClinicianNavTab(label: 'Reports', icon: Icons.folder_open_rounded),
    _ClinicianNavTab(label: 'Profile', icon: Icons.person_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _initializePushMessaging();
  }

  @override
  void dispose() {
    _foregroundSub?.cancel();
    _openedAppSub?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _initializePushMessaging() async {
    await ClinicianPushService.instance.startForClinician();

    _foregroundSub = ClinicianPushService.instance.foregroundMessages.listen((message) {
      if (!mounted) return;
      _showEmergencyDialog(message);
    });

    _openedAppSub = ClinicianPushService.instance.openedAppMessages.listen((_) {
      if (!mounted) return;
      _jumpTo(1);
    });
  }

  Future<void> _showEmergencyDialog(RemoteMessage message) async {
    final title =
        message.notification?.title ?? 'High-priority wellness alert';
    final body = message.notification?.body ??
        'A linked patient may need immediate support.';

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Dismiss'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _jumpTo(1);
            },
            child: const Text('View Reports'),
          ),
        ],
      ),
    );
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
            .map((tab) => BottomNavigationBarItem(icon: Icon(tab.icon), label: tab.label))
            .toList(growable: false),
      ),
    );
  }
}

class _ClinicianNavTab {
  const _ClinicianNavTab({required this.label, required this.icon});

  final String label;
  final IconData icon;
}
