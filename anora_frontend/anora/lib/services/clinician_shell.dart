import 'package:anora/services/report_service.dart';
import 'package:anora/clinician/patient_feed_tab.dart';
import 'package:anora/clinician/patient_list_tab.dart';
import 'package:anora/clinician/clinician_settings_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ClinicianShell extends StatefulWidget {
  final String clinicianId;
  const ClinicianShell({super.key, required this.clinicianId});

  @override
  State<ClinicianShell> createState() => _ClinicianShellState();
}

class _ClinicianShellState extends State<ClinicianShell> {
  int _selectedIndex = 0;
  late final List<Widget> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = [
      const PatientListTab(),
      PatientFeedTab(clinicianId: widget.clinicianId),
      const ClinicianSettingsTab(),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _generateAndShowInviteCode() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final code = await ReportService.instance.generateInviteCode(widget.clinicianId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Patient Invite Code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Share this single-use code with your patient to establish a secure link. The code expires in 24 hours.'),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  code,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                messenger.showSnackBar(const SnackBar(content: Text('Copied to clipboard!')));
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
      messenger.showSnackBar(SnackBar(content: Text('Failed to generate code: $e')));
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
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Patients'),
          BottomNavigationBarItem(icon: Icon(Icons.feed), label: 'Updates'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}