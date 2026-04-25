import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/home_screen.dart';
import 'screens/insights_screen.dart';
import 'screens/journal_screen.dart';
import 'screens/settings_screen.dart';
import 'onboarding/onboarding_gate.dart';
import 'services/ai_inference_service.dart';
import 'services/storage_service.dart';
import 'services/tokenizer_service.dart';
import 'widgets/app_lock_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.instance.init();
  await TokenizerService.instance.init();
  await AiInferenceService.instance.init();
  runApp(const ProviderScope(child: AnoraApp()));
}

class AnoraApp extends StatelessWidget {
  const AnoraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anora',
      debugShowCheckedModeBanner: false,
      theme: _buildSoothingTheme(),
      home: const OnboardingGate(),
    );
  }
}

ThemeData _buildSoothingTheme() {
  const colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF4D6B5B),
    onPrimary: Color(0xFFF7F6F2),
    secondary: Color(0xFF5B6F8F),
    onSecondary: Color(0xFFF7F6F2),
    error: Color(0xFFE38B7C),
    onError: Color(0xFFF7F6F2),
    surface: Color(0xFFF7F6F2),
    onSurface: Color(0xFF1F2A24),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colorScheme.surface,
    fontFamily: 'Poppins',
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
      headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontSize: 16, height: 1.6),
      bodyMedium: TextStyle(fontSize: 14, height: 1.6),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF1F0EB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF4D6B5B), width: 1.2),
      ),
      hintStyle: const TextStyle(color: Color(0xFF6E7A73)),
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: true,
      backgroundColor: Color(0xFFF7F6F2),
      foregroundColor: Color(0xFF1F2A24),
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFFF7F6F2),
      selectedItemColor: Color(0xFF4D6B5B),
      unselectedItemColor: Color(0xFF87958B),
      showUnselectedLabels: true,
      type: BottomNavigationBarType.fixed,
    ),
    dividerColor: const Color(0xFFE0DED7),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;
  late final PageController _pageController;

  final List<_NavTab> _tabs = const [
    _NavTab(label: 'Home', icon: Icons.home_rounded),
    _NavTab(label: 'Journal', icon: Icons.edit_note_rounded),
    _NavTab(label: 'Insights', icon: Icons.insights_rounded),
    _NavTab(label: 'Settings', icon: Icons.settings_rounded),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          onPageChanged: (index) => setState(() => _currentIndex = index),
          children: [
            HomeScreen(onGoToJournal: () => _jumpTo(1)),
            const JournalScreen(),
            const InsightsScreen(),
            const SettingsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => _jumpTo(index),
        items: _tabs
            .map(
              (tab) => BottomNavigationBarItem(
                icon: Icon(tab.icon),
                label: tab.label,
              ),
            )
            .toList(),
      ),
    );
  }

  void _jumpTo(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }
}

class _NavTab {
  const _NavTab({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

