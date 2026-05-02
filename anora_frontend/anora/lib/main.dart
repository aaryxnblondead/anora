import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin/admin_web_portal.dart';
import 'clinician/clinician_web_portal.dart';
import 'screens/home_screen.dart';
import 'screens/insights_screen.dart';
import 'screens/journal_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/unstuck_screen.dart';
import 'onboarding/onboarding_gate.dart';
import 'services/ai_inference_service.dart';
import 'services/storage_service.dart';
import 'services/tokenizer_service.dart';
import 'state/navigation_state.dart';
import 'theme/anora_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await StorageService.instance.init();
    await TokenizerService.instance.init();
    await AiInferenceService.instance.init();

    runApp(const ProviderScope(child: AnoraApp()));
  } catch (e, stackTrace) {
    // If anything fails during boot, catch it and show a red error screen
    // instead of silently crashing the entire app.
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Text(
                'FATAL BOOT ERROR:\n\n$e\n\n$stackTrace',
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AnoraApp extends StatelessWidget {
  const AnoraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anora',
      debugShowCheckedModeBanner: false,
      theme: buildAnoraTheme(),
      home: _isAdminWebPortalMode()
          ? const AdminWebPortalGate()
          : _isClinicianWebPortalMode()
              ? const ClinicianWebPortalGate()
              : const OnboardingGate(),
    );
  }
}

bool _isAdminWebPortalMode() {
  if (!kIsWeb) return false;

  final uri = Uri.base;
  final portal = uri.queryParameters['portal']?.toLowerCase();
  if (portal == 'admin' || portal == 'ops' || portal == 'monitor') {
    return true;
  }

  final path = uri.path.toLowerCase();
  if (path.contains('admin-portal') || path.endsWith('/admin')) {
    return true;
  }

  final fragment = uri.fragment.toLowerCase();
  return fragment.contains('portal=admin') ||
      fragment.contains('admin-portal');
}

bool _isClinicianWebPortalMode() {
  if (!kIsWeb) return false;

  final uri = Uri.base;
  final portal = uri.queryParameters['portal']?.toLowerCase();
  if (portal == 'clinician' || portal == 'clinician-web') {
    return true;
  }

  final path = uri.path.toLowerCase();
  if (path.contains('clinician-portal') || path.endsWith('/clinician')) {
    return true;
  }

  final fragment = uri.fragment.toLowerCase();
  return fragment.contains('portal=clinician') ||
      fragment.contains('clinician-portal');
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _currentIndex = 0;
  late final PageController _pageController;

  final List<_NavTab> _tabs = const [
    _NavTab(
      label: 'Home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
    ),
    _NavTab(
      label: 'Unstuck',
      icon: Icons.self_improvement_outlined,
      selectedIcon: Icons.self_improvement_rounded,
    ),
    _NavTab(
      label: 'Journal',
      icon: Icons.edit_note_outlined,
      selectedIcon: Icons.edit_note_rounded,
    ),
    _NavTab(
      label: 'Insights',
      icon: Icons.insights_outlined,
      selectedIcon: Icons.insights_rounded,
    ),
    _NavTab(
      label: 'Settings',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    // Listen for navigation requests from other parts of the app.
    ref.listen<int?>(navRequestProvider, (previous, next) {
      if (next != null) {
        _jumpTo(next);
        // clear the request
        Future.microtask(() => ref.read(navRequestProvider.notifier).state = null);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = AnoraLayoutSpec.of(context);

    return AnoraBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            onPageChanged: (index) => setState(() => _currentIndex = index),
            children: [
              HomeScreen(
                onGoToJournal: () => _jumpTo(2),
                onGoToUnstuck: () => _jumpTo(1),
              ),
              UnstuckScreen(onGoToJournal: () => _jumpTo(2)),
              const JournalScreen(),
              const InsightsScreen(),
              const SettingsScreen(),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          minimum: EdgeInsets.fromLTRB(
            layout.isCompact ? 10 : 12,
            0,
            layout.isCompact ? 10 : 12,
            layout.isCompact ? 8 : 10,
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A163556),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: NavigationBar(
                selectedIndex: _currentIndex,
                onDestinationSelected: (index) => _jumpTo(index),
                destinations: _tabs
                    .map(
                      (tab) => NavigationDestination(
                        icon: Icon(tab.icon),
                        selectedIcon: Icon(tab.selectedIcon),
                        label: tab.label,
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _jumpTo(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: AnoraMotion.standard,
      curve: AnoraMotion.standardCurve,
    );
  }
}

class _NavTab {
  const _NavTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
