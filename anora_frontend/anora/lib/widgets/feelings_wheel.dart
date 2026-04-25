import 'dart:math';

import 'package:flutter/material.dart';

const double _wheelSize = 560;
const double _r1 = 66;
const double _r2 = 142;
const double _r3 = 218;
const double _r4 = 274;

class FeelingNode {
  const FeelingNode({
    required this.id,
    required this.label,
    required this.colors,
    required this.children,
  });

  final String id;
  final String label;
  final List<Color> colors;
  final List<FeelingBranch> children;
}

class FeelingBranch {
  const FeelingBranch({required this.label, required this.children});

  final String label;
  final List<String> children;
}

class FeelingsWheelData {
  static const feelings = [
    FeelingNode(
      id: 'bad',
      label: 'Bad',
      colors: [Color(0xFF4CBFB4), Color(0xFF74D0C9), Color(0xFF9EDFD9)],
      children: [
        FeelingBranch(label: 'Bored', children: ['Indifferent', 'Apathetic']),
        FeelingBranch(label: 'Busy', children: ['Pressured', 'Rushed']),
        FeelingBranch(
          label: 'Stressed',
          children: ['Overwhelmed', 'Out of control'],
        ),
        FeelingBranch(label: 'Tired', children: ['Sleepy', 'Unfocused']),
      ],
    ),
    FeelingNode(
      id: 'fearful',
      label: 'Fearful',
      colors: [Color(0xFF42B8D4), Color(0xFF70CADF), Color(0xFF9EDBE9)],
      children: [
        FeelingBranch(label: 'Scared', children: ['Helpless', 'Frightened']),
        FeelingBranch(
          label: 'Anxious',
          children: ['Overwhelmed', 'Worried'],
        ),
        FeelingBranch(
          label: 'Insecure',
          children: ['Inadequate', 'Inferior'],
        ),
        FeelingBranch(label: 'Weak', children: ['Worthless', 'Insignificant']),
        FeelingBranch(label: 'Rejected', children: ['Excluded', 'Persecuted']),
        FeelingBranch(label: 'Threatened', children: ['Nervous', 'Exposed']),
      ],
    ),
    FeelingNode(
      id: 'angry',
      label: 'Angry',
      colors: [Color(0xFF6860A6), Color(0xFF8A83BF), Color(0xFFACA7D8)],
      children: [
        FeelingBranch(label: 'Let down', children: ['Betrayed', 'Resentful']),
        FeelingBranch(
          label: 'Humiliated',
          children: ['Disrespected', 'Ridiculed'],
        ),
        FeelingBranch(label: 'Bitter', children: ['Indignant', 'Violated']),
        FeelingBranch(label: 'Mad', children: ['Furious', 'Jealous']),
        FeelingBranch(
          label: 'Aggressive',
          children: ['Provoked', 'Hostile'],
        ),
        FeelingBranch(label: 'Frustrated', children: ['Infuriated', 'Annoyed']),
        FeelingBranch(label: 'Distant', children: ['Withdrawn', 'Numb']),
        FeelingBranch(label: 'Critical', children: ['Sceptical', 'Dismissive']),
      ],
    ),
    FeelingNode(
      id: 'disgusted',
      label: 'Disgusted',
      colors: [Color(0xFF987DA4), Color(0xFFB29BBD), Color(0xFFCCBAD6)],
      children: [
        FeelingBranch(
          label: 'Disapproving',
          children: ['Judgmental', 'Embarrassed'],
        ),
        FeelingBranch(
          label: 'Disappointed',
          children: ['Appalled', 'Revolted'],
        ),
        FeelingBranch(label: 'Awful', children: ['Nauseated', 'Detestable']),
        FeelingBranch(label: 'Repelled', children: ['Horrified', 'Hesitant']),
      ],
    ),
    FeelingNode(
      id: 'sad',
      label: 'Sad',
      colors: [Color(0xFFCC78A0), Color(0xFFDA9BBC), Color(0xFFE8BED6)],
      children: [
        FeelingBranch(label: 'Hurt', children: ['Embarrassed', 'Disappointed']),
        FeelingBranch(label: 'Depressed', children: ['Inferior', 'Empty']),
        FeelingBranch(label: 'Guilty', children: ['Remorseful', 'Ashamed']),
        FeelingBranch(label: 'Despair', children: ['Powerless', 'Grief']),
        FeelingBranch(label: 'Vulnerable', children: ['Fragile', 'Victimised']),
        FeelingBranch(label: 'Lonely', children: ['Abandoned', 'Isolated']),
      ],
    ),
    FeelingNode(
      id: 'happy',
      label: 'Happy',
      colors: [Color(0xFFE5745A), Color(0xFFED9880), Color(0xFFF4BCA7)],
      children: [
        FeelingBranch(label: 'Playful', children: ['Aroused', 'Cheeky']),
        FeelingBranch(label: 'Content', children: ['Free', 'Joyful']),
        FeelingBranch(label: 'Interested', children: ['Curious', 'Inquisitive']),
        FeelingBranch(label: 'Proud', children: ['Successful', 'Confident']),
        FeelingBranch(label: 'Accepted', children: ['Respected', 'Valued']),
        FeelingBranch(label: 'Powerful', children: ['Courageous', 'Creative']),
        FeelingBranch(label: 'Peaceful', children: ['Loving', 'Thankful']),
        FeelingBranch(label: 'Trusting', children: ['Sensitive', 'Intimate']),
        FeelingBranch(label: 'Optimistic', children: ['Hopeful', 'Inspired']),
      ],
    ),
    FeelingNode(
      id: 'surprised',
      label: 'Surprised',
      colors: [Color(0xFFEDA020), Color(0xFFF5BA5A), Color(0xFFFAD598)],
      children: [
        FeelingBranch(label: 'Startled', children: ['Shocked', 'Dismayed']),
        FeelingBranch(
          label: 'Confused',
          children: ['Disillusioned', 'Perplexed'],
        ),
        FeelingBranch(label: 'Amazed', children: ['Astonished', 'Awe']),
        FeelingBranch(label: 'Excited', children: ['Eager', 'Energetic']),
      ],
    ),
  ];

  static const journalPrompts = {
    'happy': "What's brought this joy into your day?",
    'sad': "What's weighing on your heart right now?",
    'angry': "What's triggered this feeling in you?",
    'fearful': 'What are you worried might happen?',
    'disgusted': 'What has been bothering you?',
    'bad': "What's been draining your energy lately?",
    'surprised': 'What caught you completely off guard?',
  };

  static double moodScoreForPath(List<String> path) {
    if (path.isEmpty) return 0.5;
    const baseScores = {
      'Happy': 0.9,
      'Surprised': 0.75,
      'Bad': 0.55,
      'Fearful': 0.35,
      'Angry': 0.25,
      'Disgusted': 0.18,
      'Sad': 0.08,
    };

    final core = path.first;
    var score = baseScores[core] ?? 0.5;
    if (path.length > 1) {
      final coreNode = feelings.firstWhere(
        (node) => node.label == core,
        orElse: () => feelings.first,
      );
      final childIndex = coreNode.children.indexWhere(
        (child) => child.label == path[1],
      );
      if (childIndex >= 0 && coreNode.children.length > 1) {
        final offset = (childIndex / (coreNode.children.length - 1)) - 0.5;
        score += offset * 0.08;
      }
    }
    if (path.length > 2) {
      final coreNode = feelings.firstWhere(
        (node) => node.label == core,
        orElse: () => feelings.first,
      );
      final childNode = coreNode.children.firstWhere(
        (child) => child.label == path[1],
        orElse: () => coreNode.children.first,
      );
      final grandIndex = childNode.children.indexWhere(
        (child) => child == path[2],
      );
      if (grandIndex >= 0 && childNode.children.length > 1) {
        final offset = (grandIndex / (childNode.children.length - 1)) - 0.5;
        score += offset * 0.05;
      }
    }

    return score.clamp(0.0, 1.0);
  }
}

class FeelingsWheel extends StatefulWidget {
  const FeelingsWheel({
    super.key,
    this.onFeelingSelected,
    this.initialPath = const [],
  });

  final ValueChanged<List<String>>? onFeelingSelected;
  final List<String> initialPath;

  @override
  State<FeelingsWheel> createState() => _FeelingsWheelState();
}

class _FeelingsWheelState extends State<FeelingsWheel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinController;
  late final Animation<double> _spinAnimation;

  String? _selectedCoreId;
  String? _selectedSecondId;
  String? _selectedThirdId;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _spinAnimation = CurvedAnimation(
      parent: _spinController,
      curve: Curves.easeOutCubic,
    );
    _spinController.forward();
    _applyInitialPath();
    WidgetsBinding.instance.addPostFrameCallback((_) => _emitSelection());
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final breadcrumbs = _buildBreadcrumbs();
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = min(constraints.maxWidth, _wheelSize);
        final scale = maxWidth / _wheelSize;

        return Column(
          children: [
            _buildHeader(context),
            const SizedBox(height: 16),
            _buildBreadcrumbsRow(breadcrumbs),
            const SizedBox(height: 12),
            SizedBox(
              width: maxWidth,
              height: maxWidth,
              child: GestureDetector(
                onTapUp: (details) => _handleTap(details.localPosition, scale),
                onPanDown: (details) => _handleTap(details.localPosition, scale),
                onPanUpdate: (details) => _handleTap(details.localPosition, scale),
                child: AnimatedBuilder(
                  animation: _spinAnimation,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _FeelingsWheelPainter(
                        feelings: FeelingsWheelData.feelings,
                        selectedCoreId: _selectedCoreId,
                        selectedSecondId: _selectedSecondId,
                        selectedThirdId: _selectedThirdId,
                        scale: scale,
                      ),
                    );
                  },
                ),
              ),
            ),
            if (_selectedCoreId != null) ...[
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: _reset,
                style: OutlinedButton.styleFrom(
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 8,
                  ),
                  side: const BorderSide(color: Color(0xFFD8D2C8), width: 1.5),
                  foregroundColor: const Color(0xFF7A7068),
                ),
                child: const Text(
                  'Reset',
                  style: TextStyle(fontSize: 12, letterSpacing: 0.3),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      children: [
        Text(
          'How are you feeling?',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'Tap to explore your emotional landscape',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFFB0A898),
                letterSpacing: 0.2,
              ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildBreadcrumbsRow(List<_Crumb> crumbs) {
    if (crumbs.isEmpty) {
      return Text(
        'Select an emotion to begin',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFFD0C8C0),
            ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < crumbs.length; i++) ...[
          if (i > 0)
            const Text(
              '›',
              style: TextStyle(color: Color(0xFFD5CDC5), fontSize: 18),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            decoration: BoxDecoration(
              color: crumbs[i].color,
              borderRadius: BorderRadius.circular(99),
              boxShadow: [
                BoxShadow(
                  color: crumbs[i].color.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Text(
              crumbs[i].label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _reset() {
    setState(() {
      _selectedCoreId = null;
      _selectedSecondId = null;
      _selectedThirdId = null;
    });
  }

  void _applyInitialPath() {
    if (widget.initialPath.isEmpty) return;
    final coreLabel = widget.initialPath.first;
    final core = FeelingsWheelData.feelings
        .firstWhere((feeling) => feeling.label == coreLabel, orElse: () => FeelingsWheelData.feelings.first);
    _selectedCoreId = core.id;

    if (widget.initialPath.length > 1) {
      final secondLabel = widget.initialPath[1];
      final branch = core.children.firstWhere(
        (child) => child.label == secondLabel,
        orElse: () => core.children.first,
      );
      _selectedSecondId = '${core.id}||${branch.label}';

      if (widget.initialPath.length > 2 && branch.children.isNotEmpty) {
        final thirdLabel = widget.initialPath[2];
        final thirdIndex = branch.children.indexWhere((child) => child == thirdLabel);
        final resolvedThird = thirdIndex >= 0 ? branch.children[thirdIndex] : branch.children.first;
        _selectedThirdId = '${core.id}||${branch.label}||$resolvedThird';
      }
    }
  }

  FeelingNode? _currentFeeling() {
    if (_selectedCoreId == null) return null;
    return FeelingsWheelData.feelings
        .firstWhere((feeling) => feeling.id == _selectedCoreId);
  }

  List<_Crumb> _buildBreadcrumbs() {
    if (_selectedCoreId == null) return [];
    final core = _currentFeeling();
    if (core == null) return [];

    final crumbs = [
      _Crumb(label: core.label, color: core.colors[0]),
    ];

    if (_selectedSecondId != null) {
      final secondLabel = _selectedSecondId!.split('||')[1];
      final branch =
          core.children.firstWhere((child) => child.label == secondLabel);
      crumbs.add(_Crumb(label: branch.label, color: core.colors[1]));

      if (_selectedThirdId != null) {
        final thirdLabel = _selectedThirdId!.split('||')[2];
        crumbs.add(_Crumb(label: thirdLabel, color: core.colors[2]));
      }
    }

    return crumbs;
  }

  void _handleTap(Offset position, double scale) {
    final center = Offset(_wheelSize / 2, _wheelSize / 2) * scale;
    final delta = position - center;
    final distance = delta.distance / scale;
    if (distance < _r1 || distance > _r4) return;

    final angle = (atan2(delta.dy, delta.dx) * 180 / pi + 450) % 360;
    final segments = _buildSegments(selectedCoreId: _selectedCoreId);

    for (final segment in segments) {
      if (segment.contains(angle, distance)) {
        _selectSegment(segment);
        break;
      }
    }
  }

  void _selectSegment(_Segment segment) {
    setState(() {
      if (segment.type == _SegmentType.core) {
        if (_selectedCoreId == segment.id) {
          _selectedCoreId = null;
          _selectedSecondId = null;
          _selectedThirdId = null;
        } else {
          _selectedCoreId = segment.id;
          _selectedSecondId = null;
          _selectedThirdId = null;
        }
      } else if (segment.type == _SegmentType.second) {
        _selectedCoreId = segment.coreId;
        if (_selectedSecondId == segment.id) {
          _selectedSecondId = null;
          _selectedThirdId = null;
        } else {
          _selectedSecondId = segment.id;
          _selectedThirdId = null;
        }
      } else {
        _selectedCoreId = segment.coreId;
        _selectedSecondId = segment.secondId;
        _selectedThirdId = _selectedThirdId == segment.id ? null : segment.id;
      }
    });

    _emitSelection();
  }

  void _emitSelection() {
    if (widget.onFeelingSelected == null) return;
    final crumbs = _buildBreadcrumbs();
    widget.onFeelingSelected!(crumbs.map((crumb) => crumb.label).toList());
  }

  List<_Segment> _buildSegments({String? selectedCoreId}) {
    final segments = <_Segment>[];
    final totalSecond = FeelingsWheelData.feelings
        .fold<int>(0, (sum, node) => sum + node.children.length);
    final dpS = 360 / totalSecond;
    var angle = 0.0;

    for (final feeling in FeelingsWheelData.feelings) {
      final coreSweep = feeling.children.length * dpS;
      final endAngle = angle + coreSweep;
      segments.add(
        _Segment(
          type: _SegmentType.core,
          id: feeling.id,
          label: feeling.label,
          color: feeling.colors[0],
          coreId: feeling.id,
          startAngle: angle,
          endAngle: endAngle,
          innerRadius: _r1,
          outerRadius: _r2,
        ),
      );

      if (selectedCoreId != null && selectedCoreId == feeling.id) {
        for (var i = 0; i < feeling.children.length; i++) {
          final branch = feeling.children[i];
          final secondStart = angle + i * dpS;
          final secondEnd = secondStart + dpS;
          final secondId = '${feeling.id}||${branch.label}';
          segments.add(
            _Segment(
              type: _SegmentType.second,
              id: secondId,
              label: branch.label,
              color: feeling.colors[1],
              coreId: feeling.id,
              secondId: secondId,
              startAngle: secondStart,
              endAngle: secondEnd,
              innerRadius: _r2,
              outerRadius: _r3,
            ),
          );

          for (var t = 0; t < branch.children.length; t++) {
            final thirdStart =
                secondStart + (t * dpS) / branch.children.length;
            final thirdEnd =
                secondStart + ((t + 1) * dpS) / branch.children.length;
            segments.add(
              _Segment(
                type: _SegmentType.third,
                id: '${feeling.id}||${branch.label}||${branch.children[t]}',
                label: branch.children[t],
                color: feeling.colors[2],
                coreId: feeling.id,
                secondId: secondId,
                startAngle: thirdStart,
                endAngle: thirdEnd,
                innerRadius: _r3,
                outerRadius: _r4,
              ),
            );
          }
        }
      }

      angle = endAngle;
    }

    return segments;
  }
}

class _Crumb {
  const _Crumb({required this.label, required this.color});

  final String label;
  final Color color;
}

enum _SegmentType { core, second, third }

class _Segment {
  _Segment({
    required this.type,
    required this.id,
    required this.label,
    required this.color,
    required this.coreId,
    required this.startAngle,
    required this.endAngle,
    required this.innerRadius,
    required this.outerRadius,
    this.secondId,
  });

  final _SegmentType type;
  final String id;
  final String label;
  final Color color;
  final String coreId;
  final String? secondId;
  final double startAngle;
  final double endAngle;
  final double innerRadius;
  final double outerRadius;

  bool contains(double angle, double radius) {
    final withinRadius = radius >= innerRadius && radius <= outerRadius;
    final withinAngle = angle >= startAngle && angle <= endAngle;
    return withinRadius && withinAngle;
  }
}

class _FeelingsWheelPainter extends CustomPainter {
  _FeelingsWheelPainter({
    required this.feelings,
    required this.selectedCoreId,
    required this.selectedSecondId,
    required this.selectedThirdId,
    required this.scale,
  });

  final List<FeelingNode> feelings;
  final String? selectedCoreId;
  final String? selectedSecondId;
  final String? selectedThirdId;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final segments = _buildSegments();
    final center = Offset(size.width / 2, size.height / 2);
    final r1 = _r1 * scale;

    for (final segment in segments) {
      final isSelected = segment.isSelected(
        selectedCoreId,
        selectedSecondId,
        selectedThirdId,
      );
      final opacity = _opacityFor(segment);
      final paint = Paint()..color = segment.color.withOpacity(opacity);
      final path = _makeArc(
        center,
        segment.innerRadius * scale,
        segment.outerRadius * scale,
        segment.startAngle,
        segment.endAngle,
      );
      canvas.drawPath(path, paint);

      if (isSelected) {
        final stroke = Paint()
          ..color = const Color(0x8CFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8;
        canvas.drawPath(path, stroke);
      }

      if ((segment.endAngle - segment.startAngle) > 3.2) {
        _drawLabel(canvas, center, segment, isSelected);
      }
    }

    final centerPaint = Paint()..color = const Color(0xFFF9F5F0);
    canvas.drawCircle(center, r1 - 3, centerPaint);

    if (selectedCoreId != null) {
      final feeling =
          feelings.firstWhere((element) => element.id == selectedCoreId);
      final emojiPainter = TextPainter(
        text: TextSpan(
          text: _emojiFor(feeling.id),
          style: TextStyle(fontSize: 26 * scale),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      emojiPainter.paint(
        canvas,
        center - Offset(emojiPainter.width / 2, 10 * scale),
      );

      final labelPainter = TextPainter(
        text: TextSpan(
          text: feeling.label.toUpperCase(),
          style: TextStyle(
            fontSize: 9.5 * scale,
            color: const Color(0xFFB5A99E),
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelPainter.paint(
        canvas,
        center + Offset(-labelPainter.width / 2, 12 * scale),
      );
    } else {
      final tapPainter = TextPainter(
        text: TextSpan(
          text: 'tap',
          style: TextStyle(
            fontSize: 11 * scale,
            color: const Color(0xFFCDC5BD),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tapPainter.paint(
        canvas,
        center - Offset(tapPainter.width / 2, tapPainter.height / 2),
      );
    }
  }

  List<_Segment> _buildSegments() {
    final segments = <_Segment>[];
    final totalSecond =
        feelings.fold<int>(0, (sum, node) => sum + node.children.length);
    final dpS = 360 / totalSecond;
    var angle = 0.0;

    for (final feeling in feelings) {
      final coreSweep = feeling.children.length * dpS;
      final endAngle = angle + coreSweep;
      segments.add(
        _Segment(
          type: _SegmentType.core,
          id: feeling.id,
          label: feeling.label,
          color: feeling.colors[0],
          coreId: feeling.id,
          startAngle: angle,
          endAngle: endAngle,
          innerRadius: _r1,
          outerRadius: _r2,
        ),
      );

      if (selectedCoreId != null && selectedCoreId == feeling.id) {
        for (var i = 0; i < feeling.children.length; i++) {
        final branch = feeling.children[i];
        final secondStart = angle + i * dpS;
        final secondEnd = secondStart + dpS;
        final secondId = '${feeling.id}||${branch.label}';
        segments.add(
          _Segment(
            type: _SegmentType.second,
            id: secondId,
            label: branch.label,
            color: feeling.colors[1],
            coreId: feeling.id,
            secondId: secondId,
            startAngle: secondStart,
            endAngle: secondEnd,
            innerRadius: _r2,
            outerRadius: _r3,
          ),
        );

        for (var t = 0; t < branch.children.length; t++) {
          final thirdStart = secondStart + (t * dpS) / branch.children.length;
          final thirdEnd = secondStart + ((t + 1) * dpS) / branch.children.length;
          segments.add(
            _Segment(
              type: _SegmentType.third,
              id: '${feeling.id}||${branch.label}||${branch.children[t]}',
              label: branch.children[t],
              color: feeling.colors[2],
              coreId: feeling.id,
              secondId: secondId,
              startAngle: thirdStart,
              endAngle: thirdEnd,
              innerRadius: _r3,
              outerRadius: _r4,
            ),
          );
          }
        }
      }

      angle = endAngle;
    }

    return segments;
  }

  Path _makeArc(
    Offset center,
    double r1,
    double r2,
    double a1,
    double a2, {
    double gap = 0.55,
  }) {
    final start = a1 + gap / 2;
    final end = a2 - gap / 2;
    if (end - start <= 0) return Path();
    final p1 = _polar(r2, start);
    final p3 = _polar(r1, end);

    final path = Path();
    path.moveTo(center.dx + p1.dx, center.dy + p1.dy);
    path.arcTo(
      Rect.fromCircle(center: center, radius: r2),
      _toRadians(start - 90),
      _toRadians(end - start),
      false,
    );
    path.lineTo(center.dx + p3.dx, center.dy + p3.dy);
    path.arcTo(
      Rect.fromCircle(center: center, radius: r1),
      _toRadians(end - 90),
      -_toRadians(end - start),
      false,
    );
    path.close();
    return path;
  }

  void _drawLabel(
    Canvas canvas,
    Offset center,
    _Segment segment,
    bool selected,
  ) {
    final mid = (segment.startAngle + segment.endAngle) / 2;
    final radius = (segment.innerRadius + segment.outerRadius) / 2 * scale;
    final pos = _polar(radius, mid);
    final angle = mid > 180 ? mid + 90 : mid - 90;
    final fontSize = segment.type == _SegmentType.core
        ? 13.5
        : segment.type == _SegmentType.second
            ? 9
            : 7.5;
    final label = segment.label;
    final lines = _wrapLabel(label, segment.type == _SegmentType.third ? 8 : 30);

    final textPainter = TextPainter(
      text: TextSpan(
        children: [
          for (var i = 0; i < lines.length; i++)
            TextSpan(
              text: '${lines[i]}${i == lines.length - 1 ? '' : '\n'}',
              style: TextStyle(
                fontSize: fontSize * scale,
                color: Colors.white.withOpacity(0.95),
                fontWeight: segment.type == _SegmentType.core
                    ? FontWeight.w700
                    : FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
        ],
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 80 * scale);

    canvas.save();
    canvas.translate(center.dx + pos.dx, center.dy + pos.dy);
    canvas.rotate(_toRadians(angle));
    textPainter.paint(
      canvas,
      Offset(-textPainter.width / 2, -textPainter.height / 2),
    );
    canvas.restore();
  }

  double _opacityFor(_Segment segment) {
    if (selectedCoreId == null) return 1;
    if (segment.coreId != selectedCoreId) return 0.15;
    if (selectedSecondId == null || segment.type == _SegmentType.core) return 1;
    if (segment.type == _SegmentType.third && segment.secondId != selectedSecondId) {
      return 0.3;
    }
    return 1;
  }

  Offset _polar(double r, double deg) {
    final rad = _toRadians(deg - 90);
    return Offset(r * cos(rad), r * sin(rad));
  }

  double _toRadians(double deg) => deg * pi / 180;

  List<String> _wrapLabel(String text, int max) {
    if (text.length <= max) return [text];
    final words = text.split(' ');
    if (words.length < 2) return [text];
    final half = (words.length / 2).ceil();
    return [words.take(half).join(' '), words.skip(half).join(' ')];
  }

  String _emojiFor(String id) {
    switch (id) {
      case 'bad':
        return '😞';
      case 'fearful':
        return '😨';
      case 'angry':
        return '😠';
      case 'disgusted':
        return '🤢';
      case 'sad':
        return '😢';
      case 'happy':
        return '😊';
      case 'surprised':
        return '😲';
    }
    return '🙂';
  }

  @override
  bool shouldRepaint(covariant _FeelingsWheelPainter oldDelegate) {
    return oldDelegate.selectedCoreId != selectedCoreId ||
        oldDelegate.selectedSecondId != selectedSecondId ||
        oldDelegate.selectedThirdId != selectedThirdId ||
        oldDelegate.scale != scale;
  }
}

extension on _Segment {
  bool isSelected(
    String? coreId,
    String? secondId,
    String? thirdId,
  ) {
    if (type == _SegmentType.core) return coreId == id;
    if (type == _SegmentType.second) return secondId == id;
    return thirdId == id;
  }
}
