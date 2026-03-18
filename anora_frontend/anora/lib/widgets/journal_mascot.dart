import 'dart:math' as math;
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MASCOT MOOD ENUM
// ─────────────────────────────────────────────────────────────────────────────

enum MascotMood {
  idle,
  happy,
  sad,
  angry,
  fearful,
  disgusted,
  surprised,
  thinking,
  celebrating,
  sleepy,
}

// ─────────────────────────────────────────────────────────────────────────────
// MOOD CONFIG — colours, messages, eye/mouth shapes
// ─────────────────────────────────────────────────────────────────────────────

class MoodConfig {
  final Color bodyColor;
  final Color accentColor;
  final Color cheekColor;
  final String message;
  final double mouthCurve; //  1 = big smile, -1 = deep frown
  final double eyeOpenness; //  0..1
  final bool hasTears;
  final bool hasSteam; // angry steam puffs
  final bool hasSparkles;

  const MoodConfig({
    required this.bodyColor,
    required this.accentColor,
    required this.cheekColor,
    required this.message,
    required this.mouthCurve,
    required this.eyeOpenness,
    this.hasTears = false,
    this.hasSteam = false,
    this.hasSparkles = false,
  });
}

const Map<MascotMood, MoodConfig> kMoodConfigs = {
  MascotMood.idle: MoodConfig(
    bodyColor: Color(0xFFFFD580),
    accentColor: Color(0xFFFFC040),
    cheekColor: Color(0xFFFFAA88),
    message: 'Hey there! How are you feeling?',
    mouthCurve: 0.4,
    eyeOpenness: 0.85,
  ),
  MascotMood.happy: MoodConfig(
    bodyColor: Color(0xFFFFD580),
    accentColor: Color(0xFFFFA040),
    cheekColor: Color(0xFFFF9070),
    message: "Yay! I'm so glad you're feeling good! 🎉",
    mouthCurve: 1.0,
    eyeOpenness: 0.7,
    hasSparkles: true,
  ),
  MascotMood.sad: MoodConfig(
    bodyColor: Color(0xFFB8C8E8),
    accentColor: Color(0xFF8AA8D8),
    cheekColor: Color(0xFFAABEDD),
    message: "It's okay to feel sad. I'm here with you 💙",
    mouthCurve: -0.9,
    eyeOpenness: 0.6,
    hasTears: true,
  ),
  MascotMood.angry: MoodConfig(
    bodyColor: Color(0xFFFF8870),
    accentColor: Color(0xFFFF5040),
    cheekColor: Color(0xFFFF4433),
    message: 'Take a deep breath… Let it out slowly 🔥',
    mouthCurve: -0.5,
    eyeOpenness: 0.9,
    hasSteam: true,
  ),
  MascotMood.fearful: MoodConfig(
    bodyColor: Color(0xFFB8D8E8),
    accentColor: Color(0xFF78A8C8),
    cheekColor: Color(0xFFAAC8DD),
    message: "You're safe right now. I've got you 🤍",
    mouthCurve: -0.3,
    eyeOpenness: 1.0,
  ),
  MascotMood.disgusted: MoodConfig(
    bodyColor: Color(0xFFC0D0A8),
    accentColor: Color(0xFF90B070),
    cheekColor: Color(0xFFA8B890),
    message: "Oof, that's a rough feeling to carry 🌿",
    mouthCurve: -0.4,
    eyeOpenness: 0.65,
  ),
  MascotMood.surprised: MoodConfig(
    bodyColor: Color(0xFFFFD080),
    accentColor: Color(0xFFFFB040),
    cheekColor: Color(0xFFFFAA70),
    message: 'Whoa! Something caught you off guard! ⚡',
    mouthCurve: 0.0,
    eyeOpenness: 1.0,
    hasSparkles: true,
  ),
  MascotMood.thinking: MoodConfig(
    bodyColor: Color(0xFFD8C8F0),
    accentColor: Color(0xFFAA98D8),
    cheekColor: Color(0xFFC0B0E0),
    message: 'Hmm… let me think about that with you 💭',
    mouthCurve: 0.15,
    eyeOpenness: 0.75,
  ),
  MascotMood.celebrating: MoodConfig(
    bodyColor: Color(0xFFFFD580),
    accentColor: Color(0xFFFFA040),
    cheekColor: Color(0xFFFF9070),
    message: 'Look at you! Amazing work today! 🎊',
    mouthCurve: 1.0,
    eyeOpenness: 0.65,
    hasSparkles: true,
  ),
  MascotMood.sleepy: MoodConfig(
    bodyColor: Color(0xFFD8D0E8),
    accentColor: Color(0xFFB0A8C8),
    cheekColor: Color(0xFFBBB0D0),
    message: 'Zzz… rest is important too 🌙',
    mouthCurve: 0.2,
    eyeOpenness: 0.15,
  ),
};

// ─────────────────────────────────────────────────────────────────────────────
// PARTICLE DATA  (tears, steam, sparkles)
// ─────────────────────────────────────────────────────────────────────────────

class _Particle {
  double x, y, vx, vy, size, opacity, angle;
  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.opacity,
    this.angle = 0,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// MASCOT WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class JournalMascot extends StatefulWidget {
  final MascotMood mood;
  final VoidCallback? onTap;
  final double size;

  const JournalMascot({
    super.key,
    this.mood = MascotMood.idle,
    this.onTap,
    this.size = 200,
  });

  @override
  State<JournalMascot> createState() => _JournalMascotState();
}

class _JournalMascotState extends State<JournalMascot>
    with TickerProviderStateMixin {
  // ── Controllers ──────────────────────────────────────────────────────────
  late AnimationController _breathCtrl; // slow idle float
  late AnimationController _blinkCtrl; // eye blink
  late AnimationController _bounceCtrl; // tap bounce
  late AnimationController _moodCtrl; // mood-change morph
  late AnimationController _particleCtrl; // particles
  late AnimationController _wiggleCtrl; // ear/tail wiggle

  // ── Animations ────────────────────────────────────────────────────────────
  late Animation<double> _breathAnim;
  late Animation<double> _bounceAnim;
  late Animation<double> _moodAnim;

  // ── State ─────────────────────────────────────────────────────────────────
  MascotMood _prevMood = MascotMood.idle;
  MascotMood _currentMood = MascotMood.idle;
  bool _isBlinking = false;
  bool _isTapped = false;
  final _rng = math.Random();

  final List<_Particle> _particles = [];
  double _particleTime = 0;

  @override
  void initState() {
    super.initState();

    // Breathing float
    _breathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
    _breathAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _breathCtrl, curve: Curves.easeInOut),
    );

    // Blink
    _blinkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _scheduleNextBlink();

    // Tap bounce
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _bounceAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.18)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.18, end: 0.92)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.92, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 35,
      ),
    ]).animate(_bounceCtrl);
    _bounceCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        setState(() => _isTapped = false);
      }
    });

    // Mood morph
    _moodCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _moodAnim = CurvedAnimation(parent: _moodCtrl, curve: Curves.easeInOutCubic);

    // Particles
    _particleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_tickParticles)
      ..repeat();

    // Wiggle
    _wiggleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _currentMood = widget.mood;
  }

  // ── Blink scheduling ──────────────────────────────────────────────────────
  void _scheduleNextBlink() {
    final delay = Duration(milliseconds: 2200 + _rng.nextInt(3000));
    Future.delayed(delay, () {
      if (!mounted) return;
      setState(() => _isBlinking = true);
      _blinkCtrl.forward(from: 0).then((_) {
        _blinkCtrl.reverse().then((_) {
          if (mounted) setState(() => _isBlinking = false);
          _scheduleNextBlink();
        });
      });
    });
  }

  // ── Particle tick ─────────────────────────────────────────────────────────
  void _tickParticles() {
    if (!mounted) return;
    _particleTime += 0.016;
    final cfg = kMoodConfigs[_currentMood]!;

    // Spawn
    if (cfg.hasTears && _particles.length < 6) {
      _spawnTear();
    }
    if (cfg.hasSteam && _particles.length < 8) {
      _spawnSteam();
    }
    if (cfg.hasSparkles && _rng.nextDouble() < 0.25 && _particles.length < 20) {
      _spawnSparkle();
    }

    // Update
    for (int i = _particles.length - 1; i >= 0; i--) {
      final p = _particles[i];
      p.x += p.vx;
      p.y += p.vy;
      p.opacity -= 0.018;
      if (p.opacity <= 0) _particles.removeAt(i);
    }

    setState(() {});
  }

  void _spawnTear() {
    final side = _rng.nextBool() ? -1.0 : 1.0;
    _particles.add(_Particle(
      x: 0.3 * side,
      y: -0.08,
      vx: 0.002 * side,
      vy: 0.012,
      size: 0.03,
      opacity: 0.9,
    ));
  }

  void _spawnSteam() {
    final xOff = (_rng.nextDouble() - 0.5) * 0.5;
    _particles.add(_Particle(
      x: xOff,
      y: -0.55,
      vx: (_rng.nextDouble() - 0.5) * 0.008,
      vy: -0.014 - _rng.nextDouble() * 0.006,
      size: 0.06 + _rng.nextDouble() * 0.04,
      opacity: 0.7,
    ));
  }

  void _spawnSparkle() {
    final angle = _rng.nextDouble() * math.pi * 2;
    final dist = 0.5 + _rng.nextDouble() * 0.25;
    _particles.add(_Particle(
      x: math.cos(angle) * dist,
      y: math.sin(angle) * dist * 0.7,
      vx: math.cos(angle) * 0.009,
      vy: math.sin(angle) * 0.009 - 0.005,
      size: 0.025 + _rng.nextDouble() * 0.025,
      opacity: 1.0,
      angle: _rng.nextDouble() * math.pi * 2,
    ));
  }

  // ── Mood change ───────────────────────────────────────────────────────────
  @override
  void didUpdateWidget(JournalMascot old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood) {
      _prevMood = _currentMood;
      _currentMood = widget.mood;
      _particles.clear();
      _moodCtrl.forward(from: 0);

      // Auto-celebrate wiggle
      if (widget.mood == MascotMood.celebrating ||
          widget.mood == MascotMood.happy) {
        _bounceCtrl.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _breathCtrl.dispose();
    _blinkCtrl.dispose();
    _bounceCtrl.dispose();
    _moodCtrl.dispose();
    _particleCtrl.dispose();
    _wiggleCtrl.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        widget.onTap?.call();
        _bounceCtrl.forward(from: 0);
        setState(() => _isTapped = true);
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _breathAnim,
          _bounceAnim,
          _moodAnim,
          _wiggleCtrl,
        ]),
        builder: (ctx, _) {
          final breath = _breathAnim.value;
          final bounce = _bounceCtrl.isAnimating ? _bounceAnim.value : 1.0;
          final t = _moodAnim.value;
          final wiggle = _wiggleCtrl.value;

          final prevCfg = kMoodConfigs[_prevMood]!;
          final currCfg = kMoodConfigs[_currentMood]!;

          // Lerp mood properties
          final bodyColor = Color.lerp(prevCfg.bodyColor, currCfg.bodyColor, t)!;
          final accentColor =
              Color.lerp(prevCfg.accentColor, currCfg.accentColor, t)!;
          final cheekColor =
              Color.lerp(prevCfg.cheekColor, currCfg.cheekColor, t)!;
          final mouthCurve =
              lerpDouble(prevCfg.mouthCurve, currCfg.mouthCurve, t);
          final eyeOpen =
              lerpDouble(prevCfg.eyeOpenness, currCfg.eyeOpenness, t);

          // Apply blink on top
          final finalEyeOpen = _isBlinking ? 0.05 : eyeOpen;

          final s = widget.size;

          return Transform.scale(
            scale: bounce,
            child: SizedBox(
              width: s,
              height: s * 1.2,
              child: CustomPaint(
                painter: _MascotPainter(
                  bodyColor: bodyColor,
                  accentColor: accentColor,
                  cheekColor: cheekColor,
                  mouthCurve: mouthCurve,
                  eyeOpenness: finalEyeOpen,
                  breath: breath,
                  wiggle: wiggle,
                  particles: List.from(_particles),
                  mood: _currentMood,
                  prevCfg: prevCfg,
                  currCfg: currCfg,
                  moodT: t,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

double lerpDouble(double a, double b, double t) => a + (b - a) * t;

// ─────────────────────────────────────────────────────────────────────────────
// CUSTOM PAINTER
// ─────────────────────────────────────────────────────────────────────────────

class _MascotPainter extends CustomPainter {
  final Color bodyColor, accentColor, cheekColor;
  final double mouthCurve, eyeOpenness, breath, wiggle, moodT;
  final MascotMood mood;
  final MoodConfig prevCfg, currCfg;
  final List<_Particle> particles;

  const _MascotPainter({
    required this.bodyColor,
    required this.accentColor,
    required this.cheekColor,
    required this.mouthCurve,
    required this.eyeOpenness,
    required this.breath,
    required this.wiggle,
    required this.particles,
    required this.mood,
    required this.prevCfg,
    required this.currCfg,
    required this.moodT,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 + size.height * 0.04;
    final r = size.width * 0.38;

    // Breathing offsets
    final floatY = -breath * size.height * 0.018;
    final breathScX = 1.0 + breath * 0.012;
    final breathScY = 1.0 - breath * 0.008;

    canvas.save();
    canvas.translate(cx, cy + floatY);

    _drawShadow(canvas, r, breath);
    _drawTail(canvas, r, wiggle);
    _drawEars(canvas, r, wiggle);
    _drawBody(canvas, r, breathScX, breathScY);
    _drawBelly(canvas, r);
    _drawCheeks(canvas, r);
    _drawEyes(canvas, r);
    _drawMouth(canvas, r);
    _drawNose(canvas, r);
    if (mood == MascotMood.thinking) _drawThoughtBubble(canvas, r);
    if (mood == MascotMood.sleepy) _drawZzz(canvas, r);
    _drawParticles(canvas, r);

    canvas.restore();
  }

  // ── Shadow ────────────────────────────────────────────────────────────────
  void _drawShadow(Canvas canvas, double r, double breath) {
    final sPaint = Paint()
      ..color = Colors.black.withOpacity(0.08 + breath * 0.03)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, r * 0.95),
        width: r * 1.5,
        height: r * 0.3,
      ),
      sPaint,
    );
  }

  // ── Ears ──────────────────────────────────────────────────────────────────
  void _drawEars(Canvas canvas, double r, double wiggle) {
    final earPaint = Paint()..color = accentColor;
    final innerPaint = Paint()..color = cheekColor.withOpacity(0.6);

    for (final side in [-1.0, 1.0]) {
      final wiggleAngle = side * wiggle * 0.14;
      canvas.save();
      canvas.translate(side * r * 0.72, -r * 0.68);
      canvas.rotate(wiggleAngle);

      // Outer ear
      final earPath = Path()
        ..moveTo(0, 0)
        ..cubicTo(side * r * 0.22, -r * 0.18, side * r * 0.32, -r * 0.48,
            0, -r * 0.52)
        ..cubicTo(-side * r * 0.32, -r * 0.48, -side * r * 0.22, -r * 0.18,
            0, 0);
      canvas.drawPath(earPath, earPaint);

      // Inner ear
      canvas.save();
      canvas.scale(0.55, 0.55);
      canvas.drawPath(earPath, innerPaint);
      canvas.restore();

      canvas.restore();
    }
  }

  // ── Tail ─────────────────────────────────────────────────────────────────
  void _drawTail(Canvas canvas, double r, double wiggle) {
    final tailPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.12
      ..strokeCap = StrokeCap.round;

    final wag = wiggle * r * 0.22;
    final tailPath = Path()
      ..moveTo(r * 0.55, r * 0.3)
      ..cubicTo(
        r * 0.9 + wag * 0.5,
        r * 0.1,
        r * 1.1 + wag,
        r * 0.5,
        r * 0.9 + wag * 0.8,
        r * 0.7,
      );

    // Draw slightly transparent body-colored backing to look 3D
    canvas.drawPath(
      tailPath,
      Paint()
        ..color = bodyColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.18
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(tailPath, tailPaint);
  }

  // ── Body ──────────────────────────────────────────────────────────────────
  void _drawBody(Canvas canvas, double r, double scX, double scY) {
    canvas.save();
    canvas.scale(scX, scY);

    // Drop shadow for body
    final shadowPaint = Paint()
      ..color = accentColor.withOpacity(0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(2, 6),
        width: r * 2.05,
        height: r * 2.05,
      ),
      shadowPaint,
    );

    // Main body
    final bodyPaint = Paint()..color = bodyColor;
    canvas.drawCircle(Offset.zero, r, bodyPaint);

    // Specular highlight
    final gradPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.35),
        radius: 0.65,
        colors: [
          Colors.white.withOpacity(0.45),
          Colors.white.withOpacity(0.0),
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: r));
    canvas.drawCircle(Offset.zero, r, gradPaint);

    canvas.restore();
  }

  // ── Belly ─────────────────────────────────────────────────────────────────
  void _drawBelly(Canvas canvas, double r) {
    final bellyPaint = Paint()..color = Colors.white.withOpacity(0.28);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, r * 0.28),
        width: r * 0.88,
        height: r * 0.72,
      ),
      bellyPaint,
    );
  }

  // ── Cheeks ────────────────────────────────────────────────────────────────
  void _drawCheeks(Canvas canvas, double r) {
    final cheekPaint = Paint()
      ..color = cheekColor.withOpacity(0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    for (final side in [-1.0, 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(side * r * 0.46, r * 0.12),
          width: r * 0.34,
          height: r * 0.22,
        ),
        cheekPaint,
      );
    }
  }

  // ── Nose ─────────────────────────────────────────────────────────────────
  void _drawNose(Canvas canvas, double r) {
    final p = Paint()..color = accentColor.withOpacity(0.85);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, -r * 0.06),
        width: r * 0.16,
        height: r * 0.1,
      ),
      p,
    );
  }

  // ── Eyes ─────────────────────────────────────────────────────────────────-
  void _drawEyes(Canvas canvas, double r) {
    final eyeY = -r * 0.22;
    final eyeXL = -r * 0.28;
    final eyeXR = r * 0.28;
    final eyeW = r * 0.2;
    final eyeH = r * 0.22 * eyeOpenness.clamp(0.05, 1.0);

    // Eye whites
    final whitePaint = Paint()..color = Colors.white.withOpacity(0.92);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(eyeXL, eyeY),
        width: eyeW,
        height: eyeH * 1.1,
      ),
      whitePaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(eyeXR, eyeY),
        width: eyeW,
        height: eyeH * 1.1,
      ),
      whitePaint,
    );

    // Pupils
    if (eyeOpenness > 0.12) {
      final pupilPaint = Paint()..color = const Color(0xFF2A2020);
      final pr = eyeH * 0.52;
      canvas.drawCircle(Offset(eyeXL + r * 0.016, eyeY), pr, pupilPaint);
      canvas.drawCircle(Offset(eyeXR + r * 0.016, eyeY), pr, pupilPaint);

      // Pupil shine
      final shinePaint = Paint()..color = Colors.white.withOpacity(0.85);
      canvas.drawCircle(
        Offset(eyeXL + pr * 0.4, eyeY - pr * 0.4),
        pr * 0.36,
        shinePaint,
      );
      canvas.drawCircle(
        Offset(eyeXR + pr * 0.4, eyeY - pr * 0.4),
        pr * 0.36,
        shinePaint,
      );
    }

    // Sleepy eyelids
    if (eyeOpenness < 0.5) {
      final lidPaint = Paint()..color = bodyColor;
      final lidH = eyeH * (1.0 - eyeOpenness * 2).clamp(0.0, 1.0);
      canvas.drawRect(
        Rect.fromLTWH(eyeXL - eyeW / 2, eyeY - eyeH / 2, eyeW, lidH + 2),
        lidPaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(eyeXR - eyeW / 2, eyeY - eyeH / 2, eyeW, lidH + 2),
        lidPaint,
      );
    }

    // Angry eyebrows
    if (mood == MascotMood.angry) {
      final browPaint = Paint()
        ..color = accentColor.withOpacity(0.8 * moodT)
        ..strokeWidth = r * 0.055
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(eyeXL - eyeW * 0.4, eyeY - eyeH * 0.78),
        Offset(eyeXL + eyeW * 0.3, eyeY - eyeH * 1.1),
        browPaint,
      );
      canvas.drawLine(
        Offset(eyeXR - eyeW * 0.3, eyeY - eyeH * 1.1),
        Offset(eyeXR + eyeW * 0.4, eyeY - eyeH * 0.78),
        browPaint,
      );
    }

    // Fearful eyebrows (raised arches)
    if (mood == MascotMood.fearful) {
      final browPaint = Paint()
        ..color = accentColor.withOpacity(0.7 * moodT)
        ..strokeWidth = r * 0.05
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      for (final side in [-1.0, 1.0]) {
        final bx = side * r * 0.28;
        final by = eyeY - eyeH * 1.0;
        final browPath = Path()
          ..moveTo(bx - eyeW * 0.4, by + r * 0.06)
          ..cubicTo(
            bx,
            by - r * 0.08,
            bx,
            by - r * 0.08,
            bx + eyeW * 0.4,
            by + r * 0.06,
          );
        canvas.drawPath(browPath, browPaint);
      }
    }
  }

  // ── Mouth ─────────────────────────────────────────────────────────────────
  void _drawMouth(Canvas canvas, double r) {
    final mouthPaint = Paint()
      ..color = accentColor.withOpacity(0.9)
      ..strokeWidth = r * 0.07
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final mx = 0.0;
    final my = r * 0.22;
    final hw = r * 0.26;
    final cy1 = my + mouthCurve * r * 0.18;
    final cy2 = my + mouthCurve * r * 0.18;

    // Mouth fill for open/smile
    if (mouthCurve > 0.6) {
      final mouthFill =
          Paint()..color = const Color(0xFFCC5544).withOpacity(0.7);
      final mfPath = Path()
        ..moveTo(mx - hw, my)
        ..cubicTo(
          mx - hw * 0.3,
          cy1,
          mx + hw * 0.3,
          cy2,
          mx + hw,
          my,
        )
        ..cubicTo(
          mx + hw * 0.3,
          my + r * 0.14,
          mx - hw * 0.3,
          my + r * 0.14,
          mx - hw,
          my,
        )
        ..close();
      canvas.drawPath(mfPath, mouthFill);

      // Teeth
      final teethPaint = Paint()..color = Colors.white.withOpacity(0.85);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(mx - hw * 0.45, my, hw * 0.9, r * 0.07),
          const Radius.circular(3),
        ),
        teethPaint,
      );
    }

    // Mouth outline
    final mouthPath = Path()
      ..moveTo(mx - hw, my)
      ..cubicTo(mx - hw * 0.3, cy1, mx + hw * 0.3, cy2, mx + hw, my);
    canvas.drawPath(mouthPath, mouthPaint);
  }

  // ── Thought bubble ───────────────────────────────────────────────────────-
  void _drawThoughtBubble(Canvas canvas, double r) {
    final p = Paint()..color = Colors.white.withOpacity(0.7 * moodT);
    final radii = [r * 0.08, r * 0.11, r * 0.15];
    final positions = [
      Offset(r * 0.55, -r * 0.62),
      Offset(r * 0.7, -r * 0.78),
      Offset(r * 0.85, -r * 0.96),
    ];
    for (int i = 0; i < radii.length; i++) {
      canvas.drawCircle(positions[i], radii[i], p);
    }
    // Dots inside biggest bubble
    final dotP = Paint()..color = bodyColor.withOpacity(0.5 * moodT);
    for (int i = 0; i < 3; i++) {
      canvas.drawCircle(
        Offset(r * 0.72 + i * r * 0.14, -r * 0.96),
        r * 0.032,
        dotP,
      );
    }
  }

  // ── Zzz for sleepy ───────────────────────────────────────────────────────-
  void _drawZzz(Canvas canvas, double r) {
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final positions = [
      Offset(r * 0.55, -r * 0.55),
      Offset(r * 0.72, -r * 0.75),
      Offset(r * 0.9, -r * 0.98),
    ];
    final sizes = [r * 0.22, r * 0.28, r * 0.34];
    for (int i = 0; i < 3; i++) {
      textPainter.text = TextSpan(
        text: 'z',
        style: TextStyle(
          fontSize: sizes[i],
          color: accentColor.withOpacity(0.7 * moodT),
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, positions[i]);
    }
  }

  // ── Particles ─────────────────────────────────────────────────────────────
  void _drawParticles(Canvas canvas, double r) {
    for (final p in particles) {
      final px = p.x * r;
      final py = p.y * r;
      final ps = p.size * r;

      if (currCfg.hasTears) {
        // Teardrop
        final tearPaint = Paint()
          ..color = const Color(0xFF88AADD).withOpacity(p.opacity)
          ..style = PaintingStyle.fill;
        final tearPath = Path()
          ..moveTo(px, py - ps)
          ..cubicTo(
            px + ps * 0.6,
            py - ps * 0.4,
            px + ps * 0.6,
            py + ps * 0.6,
            px,
            py + ps,
          )
          ..cubicTo(
            px - ps * 0.6,
            py + ps * 0.6,
            px - ps * 0.6,
            py - ps * 0.4,
            px,
            py - ps,
          )
          ..close();
        canvas.drawPath(tearPath, tearPaint);
      } else if (currCfg.hasSteam) {
        // Steam puff
        final steamPaint = Paint()
          ..color = const Color(0xFFFF7755).withOpacity(p.opacity * 0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
        canvas.drawCircle(Offset(px, py), ps, steamPaint);
      } else if (currCfg.hasSparkles) {
        // Star sparkle
        final sparklePaint = Paint()
          ..color = Colors.white.withOpacity(p.opacity)
          ..style = PaintingStyle.fill;
        canvas.save();
        canvas.translate(px, py);
        canvas.rotate(p.angle);
        _drawStar(canvas, ps * 0.9, sparklePaint);
        canvas.restore();
      }
    }
  }

  void _drawStar(Canvas canvas, double r, Paint paint) {
    final path = Path();
    for (int i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      final rad = i.isEven ? r : r * 0.4;
      final x = math.cos(angle) * rad;
      final y = math.sin(angle) * rad;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MascotPainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// MASCOT SPEECH BUBBLE
// ─────────────────────────────────────────────────────────────────────────────

class MascotSpeechBubble extends StatefulWidget {
  final String message;
  final Color accentColor;

  const MascotSpeechBubble({
    super.key,
    required this.message,
    required this.accentColor,
  });

  @override
  State<MascotSpeechBubble> createState() => _MascotSpeechBubbleState();
}

class _MascotSpeechBubbleState extends State<MascotSpeechBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _opacity;
  String _displayedMessage = '';
  int _charIndex = 0;

  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
    _typeMessage();
  }

  @override
  void didUpdateWidget(MascotSpeechBubble old) {
    super.didUpdateWidget(old);
    if (old.message != widget.message) {
      setState(() {
        _displayedMessage = '';
        _charIndex = 0;
      });
      _ctrl.forward(from: 0);
      _typeMessage();
    }
  }

  void _typeMessage() {
    if (_charIndex >= widget.message.length) return;
    Future.delayed(const Duration(milliseconds: 28), () {
      if (!mounted) return;
      setState(() {
        _charIndex++;
        _displayedMessage = widget.message.substring(0, _charIndex);
      });
      _typeMessage();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Opacity(
        opacity: _opacity.value,
        child: Transform.scale(
          scale: _scale.value,
          alignment: Alignment.bottomCenter,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: widget.accentColor.withOpacity(0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Text(
              _displayedMessage,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF3A3030),
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
