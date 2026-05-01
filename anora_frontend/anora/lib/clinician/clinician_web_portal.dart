import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/clinician_crypto_service.dart';
import '../services/report_service.dart';
import '../services/secure_link_service.dart';
import '../services/storage_service.dart';
import '../state/clinician_state.dart';
import '../theme/anora_theme.dart';
import 'clinician_shell.dart';
import 'patient_feed_tab.dart';
import 'patient_list_tab.dart';
import 'profile_tab.dart';
import 'providers/linked_patients_provider.dart';

class ClinicianWebPortalGate extends StatefulWidget {
  const ClinicianWebPortalGate({super.key});

  @override
  State<ClinicianWebPortalGate> createState() => _ClinicianWebPortalGateState();
}

class _ClinicianWebPortalGateState extends State<ClinicianWebPortalGate> {
  final TextEditingController _clinicianIdController = TextEditingController();
  String? _clinicianId;
  String? _error;
  bool _isBootstrapping = true;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _clinicianIdController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final queryId = _readQueryClinicianId();
      String? storedClinicianId =
          (StorageService.instance.settingsBox.get('clinician_id') as String?)?.trim();

      if (queryId != null && queryId.isNotEmpty) {
        storedClinicianId = queryId;
        await StorageService.instance.settingsBox.put('clinician_id', queryId);
        await StorageService.instance.settingsBox.put('clinician_onboarding_complete', true);
      }

      if (storedClinicianId != null && storedClinicianId.isNotEmpty) {
        await _ensureClinicianBootstrap(storedClinicianId);
        if (!mounted) return;
        setState(() {
          _clinicianId = storedClinicianId;
          _isBootstrapping = false;
          _error = null;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _isBootstrapping = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBootstrapping = false;
        _error = 'Failed to initialize clinician web portal: $e';
      });
    }
  }

  String? _readQueryClinicianId() {
    if (!kIsWeb) return null;

    final queryId = Uri.base.queryParameters['clinician_id']?.trim();
    if (queryId != null && queryId.isNotEmpty) return queryId;

    final fragment = Uri.base.fragment;
    if (fragment.contains('clinician_id=')) {
      final fragmentUri = Uri.tryParse('https://anora.local/?$fragment');
      final fromFragment = fragmentUri?.queryParameters['clinician_id']?.trim();
      if (fromFragment != null && fromFragment.isNotEmpty) {
        return fromFragment;
      }
    }

    return null;
  }

  Future<void> _ensureClinicianBootstrap(String clinicianId) async {
    final normalizedClinicianId = clinicianId.trim();
    if (normalizedClinicianId.isEmpty) {
      throw ArgumentError('clinicianId must be non-empty');
    }

    if (!ClinicianCryptoService.instance.hasKeypair) {
      await ClinicianCryptoService.instance.generateAndStoreKeypair();
    }

    final publicKeyPem = ClinicianCryptoService.instance.getPublicKeyPem();
    if (publicKeyPem != null && publicKeyPem.isNotEmpty) {
      await SecureLinkService.instance.registerClinicianConnection(
        clinicianId: normalizedClinicianId,
        publicKeyPem: publicKeyPem,
      );
    }

    await SecureLinkService.instance.ensureClinicianSessionToken(
      clinicianId: normalizedClinicianId,
    );

    await StorageService.instance.settingsBox.put('clinician_id', normalizedClinicianId);
    await StorageService.instance.settingsBox.put('clinician_onboarding_complete', true);
  }

  Future<void> _submitClinicianId() async {
    final normalizedClinicianId = _clinicianIdController.text.trim();
    if (normalizedClinicianId.isEmpty) {
      setState(() {
        _error = 'Clinician ID is required.';
      });
      return;
    }

    setState(() {
      _isBootstrapping = true;
      _error = null;
    });

    try {
      await _ensureClinicianBootstrap(normalizedClinicianId);
      if (!mounted) return;
      setState(() {
        _clinicianId = normalizedClinicianId;
        _isBootstrapping = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBootstrapping = false;
        _error = 'Could not start clinician session: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = AnoraLayoutSpec.of(context);

    if (_isBootstrapping) {
      return const AnoraBackdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_clinicianId != null && _clinicianId!.isNotEmpty) {
      return ClinicianWebPortalShell(clinicianId: _clinicianId!);
    }

    return AnoraBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: layout.isExpanded ? 560 : 520),
            child: Padding(
              padding: EdgeInsets.all(layout.isCompact ? 16 : 24),
              child: AnoraStaggeredReveal(
                order: 0,
                child: AnoraSectionCard(
                  emphasis: true,
                  padding: EdgeInsets.all(layout.isExpanded ? 28 : 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AnoraScreenHeader(
                        title: 'Clinician Web Portal',
                        subtitle: 'Enter your clinician ID to open the secure dashboard.',
                      ),
                      SizedBox(height: layout.sectionGap),
                      TextField(
                        controller: _clinicianIdController,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => unawaited(_submitClinicianId()),
                        decoration: const InputDecoration(
                          labelText: 'Clinician ID',
                          hintText: 'e.g. dr_smith_01',
                        ),
                      ),
                      SizedBox(height: layout.minorGap + 4),
                      FilledButton.icon(
                        onPressed: _submitClinicianId,
                        icon: const Icon(Icons.login_rounded),
                        label: const Text('Open Portal'),
                      ),
                      AnimatedSwitcher(
                        duration: AnoraMotion.quick,
                        switchInCurve: AnoraMotion.standardCurve,
                        switchOutCurve: Curves.easeIn,
                        child: _error == null
                            ? const SizedBox.shrink()
                            : Padding(
                                key: ValueKey<String>(_error!),
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  _error!,
                                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ClinicianWebPortalShell extends ConsumerStatefulWidget {
  const ClinicianWebPortalShell({super.key, required this.clinicianId});

  final String clinicianId;

  @override
  ConsumerState<ClinicianWebPortalShell> createState() => _ClinicianWebPortalShellState();
}

class _ClinicianWebPortalShellState extends ConsumerState<ClinicianWebPortalShell> {
  int _selectedIndex = 0;
  Timer? _periodicSyncTimer;
  late final PageController _pageController;

  late final List<Widget> _tabs = [
    const PatientListTab(),
    PatientFeedTab(clinicianId: widget.clinicianId),
    const ProfileTab(),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    unawaited(_syncInbox());
    _periodicSyncTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_syncInbox()),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _periodicSyncTimer?.cancel();
    super.dispose();
  }

  void _selectTab(int index) {
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
    _pageController.animateToPage(
      index,
      duration: AnoraMotion.standard,
      curve: AnoraMotion.standardCurve,
    );
  }

  Future<void> _syncInbox() async {
    await Future.wait([
      ref.read(linkedPatientsProvider.notifier).sync(),
      ref.read(clinicianReportsProvider.notifier).syncLatestReports(),
      ref.read(clinicianReportsProvider.notifier).syncEmergencyAlerts(),
      ref.read(clinicianReportsProvider.notifier).syncLatestMoodUpdates(),
    ]);
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
    final layout = AnoraLayoutSpec.of(context);
    const sectionTitles = ['Patients', 'Updates', 'Profile'];
    const sectionSubtitles = [
      'Linked patient roster and secure detail access',
      'Live mood stream and risk signals from linked patients',
      'Identity, encryption keys, and secure session controls',
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 980) {
          return ClinicianShell(clinicianId: widget.clinicianId);
        }

        return AnoraBackdrop(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Row(
              children: [
                Container(
                  width: layout.railWidth,
                  decoration: const BoxDecoration(
                    border: Border(
                      right: BorderSide(color: AnoraPalette.border),
                    ),
                  ),
                  child: NavigationRail(
                    selectedIndex: _selectedIndex,
                    minWidth: 88,
                    backgroundColor: Colors.transparent,
                    indicatorColor: AnoraPalette.panelSoft,
                    labelType: NavigationRailLabelType.all,
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.dashboard_outlined),
                        selectedIcon: Icon(Icons.dashboard_rounded),
                        label: Text('Patients'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.feed_outlined),
                        selectedIcon: Icon(Icons.feed_rounded),
                        label: Text('Updates'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings_rounded),
                        label: Text('Settings'),
                      ),
                    ],
                    onDestinationSelected: _selectTab,
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        padding: EdgeInsets.fromLTRB(
                          layout.horizontalPadding,
                          layout.topPadding,
                          layout.horizontalPadding,
                          layout.minorGap + 6,
                        ),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: AnoraPalette.border),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Clinician Portal · ${sectionTitles[_selectedIndex]}',
                                    style: Theme.of(context).textTheme.headlineMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  AnimatedSwitcher(
                                    duration: AnoraMotion.quick,
                                    switchInCurve: AnoraMotion.standardCurve,
                                    child: Text(
                                      sectionSubtitles[_selectedIndex],
                                      key: ValueKey<int>(_selectedIndex),
                                      style: Theme.of(context).textTheme.bodyMedium,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(width: layout.minorGap),
                            IconButton(
                              onPressed: () => unawaited(_syncInbox()),
                              icon: const Icon(Icons.refresh_rounded),
                              tooltip: 'Sync now',
                            ),
                            FilledButton.icon(
                              onPressed: _generateAndShowInviteCode,
                              icon: const Icon(Icons.person_add_alt_1_rounded),
                              label: const Text('Invite Patient'),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            layout.horizontalPadding,
                            layout.sectionGap,
                            layout.horizontalPadding,
                            layout.bottomPadding,
                          ),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: layout.maxReadableWidth),
                              child: PageView(
                                controller: _pageController,
                                physics: const NeverScrollableScrollPhysics(),
                                onPageChanged: (index) => setState(() => _selectedIndex = index),
                                children: _tabs,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
