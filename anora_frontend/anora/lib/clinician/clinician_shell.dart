import 'package:flutter/material.dart';

import 'patients_tab.dart';
import 'profile_tab.dart';
import 'reports_tab.dart';

class ClinicianShell extends StatefulWidget {
  const ClinicianShell({super.key});

  @override
  State<ClinicianShell> createState() => _ClinicianShellState();
}

class _ClinicianShellState extends State<ClinicianShell> {
  int _currentIndex = 0;
  late final PageController _pageController;

  final List<_ClinicianNavTab> _tabs = const [
    _ClinicianNavTab(label: 'Patients', icon: Icons.people_rounded),
    _ClinicianNavTab(label: 'Reports', icon: Icons.folder_open_rounded),
    _ClinicianNavTab(label: 'Profile', icon: Icons.person_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
