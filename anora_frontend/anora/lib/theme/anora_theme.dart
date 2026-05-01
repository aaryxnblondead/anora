import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

class AnoraPalette {
  static const Color ink = Color(0xFF142439);
  static const Color primary = Color(0xFF15789B);
  static const Color secondary = Color(0xFF1F4675);
  static const Color accent = Color(0xFFE48E5D);
  static const Color success = Color(0xFF2E8B70);
  static const Color warning = Color(0xFFB4732A);
  static const Color danger = Color(0xFFB44F50);

  static const Color surface = Color(0xFFF5F8FC);
  static const Color panel = Color(0xFFFFFFFF);
  static const Color panelSoft = Color(0xFFEAF2FA);
  static const Color border = Color(0xFFD7E2ED);
  static const Color muted = Color(0xFF5E6F83);
}

enum AnoraViewportSize { compact, standard, expanded }

class AnoraLayoutSpec {
  const AnoraLayoutSpec._({
    required this.viewportSize,
    required this.horizontalPadding,
    required this.topPadding,
    required this.bottomPadding,
    required this.sectionGap,
    required this.minorGap,
    required this.maxReadableWidth,
    required this.railWidth,
  });

  final AnoraViewportSize viewportSize;
  final double horizontalPadding;
  final double topPadding;
  final double bottomPadding;
  final double sectionGap;
  final double minorGap;
  final double maxReadableWidth;
  final double railWidth;

  bool get isCompact => viewportSize == AnoraViewportSize.compact;
  bool get isExpanded => viewportSize == AnoraViewportSize.expanded;

  static AnoraLayoutSpec of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 380) {
      return const AnoraLayoutSpec._(
        viewportSize: AnoraViewportSize.compact,
        horizontalPadding: 14,
        topPadding: 14,
        bottomPadding: 16,
        sectionGap: 12,
        minorGap: 8,
        maxReadableWidth: 720,
        railWidth: 96,
      );
    }

    if (width < 1100) {
      return const AnoraLayoutSpec._(
        viewportSize: AnoraViewportSize.standard,
        horizontalPadding: 18,
        topPadding: 18,
        bottomPadding: 20,
        sectionGap: 14,
        minorGap: 10,
        maxReadableWidth: 900,
        railWidth: 110,
      );
    }

    return const AnoraLayoutSpec._(
      viewportSize: AnoraViewportSize.expanded,
      horizontalPadding: 24,
      topPadding: 20,
      bottomPadding: 24,
      sectionGap: 18,
      minorGap: 12,
      maxReadableWidth: 1200,
      railWidth: 124,
    );
  }

  EdgeInsets screenPadding({double? top, double? bottom}) {
    return EdgeInsets.fromLTRB(
      horizontalPadding,
      top ?? topPadding,
      horizontalPadding,
      bottom ?? bottomPadding,
    );
  }
}

class AnoraMotion {
  static const Duration quick = Duration(milliseconds: 170);
  static const Duration standard = Duration(milliseconds: 260);
  static const Duration reveal = Duration(milliseconds: 700);

  static const Curve standardCurve = Curves.easeOutCubic;
  static const Curve emphasizedCurve = Curves.easeOutQuart;
}

ThemeData buildAnoraTheme() {
  const baseScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AnoraPalette.primary,
    onPrimary: Colors.white,
    secondary: AnoraPalette.secondary,
    onSecondary: Colors.white,
    error: AnoraPalette.danger,
    onError: Colors.white,
    surface: AnoraPalette.surface,
    onSurface: AnoraPalette.ink,
  );

  final textTheme = const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      height: 1.1,
      color: AnoraPalette.ink,
    ),
    headlineMedium: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      height: 1.15,
      color: AnoraPalette.ink,
    ),
    titleLarge: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.1,
      color: AnoraPalette.ink,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: AnoraPalette.ink,
    ),
    bodyLarge: TextStyle(
      fontSize: 15,
      height: 1.55,
      color: AnoraPalette.ink,
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      height: 1.55,
      color: AnoraPalette.muted,
    ),
    bodySmall: TextStyle(
      fontSize: 12,
      height: 1.45,
      color: AnoraPalette.muted,
    ),
    labelLarge: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
      color: AnoraPalette.ink,
    ),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: baseScheme,
    scaffoldBackgroundColor: Colors.transparent,
    fontFamily: 'Poppins',
    textTheme: textTheme,
    cardTheme: CardThemeData(
      color: AnoraPalette.panel,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AnoraPalette.border),
      ),
      margin: EdgeInsets.zero,
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: AnoraPalette.ink,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AnoraPalette.ink,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFFDFEFF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: const TextStyle(color: AnoraPalette.muted),
      labelStyle: const TextStyle(color: AnoraPalette.muted),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AnoraPalette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AnoraPalette.primary, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AnoraPalette.danger),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AnoraPalette.border,
      thickness: 1,
      space: 22,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AnoraPalette.ink,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        animationDuration: AnoraMotion.quick,
        elevation: const WidgetStatePropertyAll(0),
        foregroundColor: const WidgetStatePropertyAll(Colors.white),
        minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
        textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return AnoraPalette.primary.withValues(alpha: 0.45);
          }
          if (states.contains(WidgetState.pressed)) {
            return const Color(0xFF106A88);
          }
          if (states.contains(WidgetState.hovered)) {
            return const Color(0xFF1B83A8);
          }
          return AnoraPalette.primary;
        }),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return Colors.white.withValues(alpha: 0.16);
          }
          if (states.contains(WidgetState.hovered)) {
            return Colors.white.withValues(alpha: 0.08);
          }
          return null;
        }),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        animationDuration: AnoraMotion.quick,
        minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
        textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return AnoraPalette.muted.withValues(alpha: 0.45);
          }
          if (states.contains(WidgetState.pressed)) {
            return const Color(0xFF173A66);
          }
          return AnoraPalette.secondary;
        }),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return const BorderSide(color: AnoraPalette.secondary, width: 1.2);
          }
          return const BorderSide(color: AnoraPalette.border);
        }),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return AnoraPalette.secondary.withValues(alpha: 0.08);
          }
          if (states.contains(WidgetState.hovered)) {
            return AnoraPalette.secondary.withValues(alpha: 0.04);
          }
          return null;
        }),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white.withValues(alpha: 0.95),
      indicatorColor: AnoraPalette.panelSoft,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return textTheme.bodySmall?.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          color: selected ? AnoraPalette.primary : AnoraPalette.muted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? AnoraPalette.primary : AnoraPalette.muted,
        );
      }),
      elevation: 0,
      height: 70,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      side: const BorderSide(color: AnoraPalette.border),
    ),
    chipTheme: const ChipThemeData(
      shape: StadiumBorder(side: BorderSide(color: AnoraPalette.border)),
      side: BorderSide(color: AnoraPalette.border),
      selectedColor: AnoraPalette.panelSoft,
      backgroundColor: Colors.white,
      labelStyle: TextStyle(fontWeight: FontWeight.w600),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _AnoraPageTransitionsBuilder(),
        TargetPlatform.iOS: _AnoraPageTransitionsBuilder(),
        TargetPlatform.linux: _AnoraPageTransitionsBuilder(),
        TargetPlatform.macOS: _AnoraPageTransitionsBuilder(),
        TargetPlatform.windows: _AnoraPageTransitionsBuilder(),
      },
    ),
  );
}

class AnoraBackdrop extends StatelessWidget {
  const AnoraBackdrop({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF6FAFF),
            Color(0xFFEFF5FB),
            Color(0xFFF9FBFD),
          ],
        ),
      ),
      child: Stack(
        children: [
          const Positioned(
            top: -140,
            right: -100,
            child: _GlowOrb(
              size: 320,
              color: Color(0x33238AB2),
            ),
          ),
          const Positioned(
            top: 160,
            left: -120,
            child: _GlowOrb(
              size: 280,
              color: Color(0x22336ECF),
            ),
          ),
          const Positioned(
            bottom: -120,
            right: -70,
            child: _GlowOrb(
              size: 260,
              color: Color(0x22E48E5D),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _DiagonalPatternPainter(),
              ),
            ),
          ),
          // ignore: use_null_aware_elements
          if (child != null) child!,
        ],
      ),
    );
  }
}

class AnoraScreenHeader extends StatelessWidget {
  const AnoraScreenHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.headlineMedium),
              const SizedBox(height: 6),
              Text(subtitle, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          trailing!,
        ],
      ],
    );
  }
}

class AnoraSectionCard extends StatelessWidget {
  const AnoraSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.emphasis = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final backgroundGradient = emphasis
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFFFFFF),
              Color(0xFFF3F8FE),
            ],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFFFFFF),
              Color(0xFFFAFCFF),
            ],
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: backgroundGradient,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AnoraPalette.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x120F2740),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class AnoraStaggeredReveal extends StatelessWidget {
  const AnoraStaggeredReveal({
    super.key,
    required this.child,
    this.order = 0,
  });

  final Widget child;
  final int order;

  @override
  Widget build(BuildContext context) {
    final start = (order * 0.08).clamp(0.0, 0.82);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AnoraMotion.reveal,
      curve: Interval(start, 1, curve: AnoraMotion.standardCurve),
      builder: (context, value, builtChild) {
        final eased = AnoraMotion.standardCurve.transform(value);
        return Opacity(
          opacity: eased,
          child: Transform.translate(
            offset: Offset(0, (1 - eased) * 22),
            child: builtChild,
          ),
        );
      },
      child: child,
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color,
              color.withValues(alpha: 0.12),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}

class _DiagonalPatternPainter extends CustomPainter {
  const _DiagonalPatternPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const step = 44.0;
    final paint = Paint()
      ..color = const Color(0x0F174067)
      ..strokeWidth = 1.0;

    for (double x = -size.height; x < size.width; x += step) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        paint,
      );
    }

    final dotPaint = Paint()..color = const Color(0x08174067);
    for (double y = 24; y < size.height; y += 72) {
      for (double x = 20; x < size.width; x += 88) {
        canvas.drawCircle(
          Offset(x + math.sin(y * 0.04) * 6, y),
          1.3,
          dotPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AnoraPageTransitionsBuilder extends PageTransitionsBuilder {
  const _AnoraPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: AnoraMotion.standardCurve,
      reverseCurve: Curves.easeInCubic,
    );

    final slide = Tween<Offset>(
      begin: const Offset(0.03, 0),
      end: Offset.zero,
    ).animate(curved);

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(position: slide, child: child),
    );
  }
}
