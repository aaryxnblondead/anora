import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../state/clinician_state.dart';

class ReportDetailSheet extends StatefulWidget {
  const ReportDetailSheet({
    super.key,
    required this.record,
    required this.notifier,
  });

  final PatientRecord record;
  final ClinicianReportsNotifier notifier;

  @override
  State<ReportDetailSheet> createState() => _ReportDetailSheetState();
}

class _ReportDetailSheetState extends State<ReportDetailSheet> {
  late PatientRecord _record;
  bool _decrypting = false;

  @override
  void initState() {
    super.initState();
    _record = widget.record;
  }

  Future<void> _decryptNow() async {
    if (_decrypting) return;
    setState(() => _decrypting = true);
    try {
      await widget.notifier.decryptRecord(_record.reportId);
      if (!mounted) return;
      _refreshFromNotifier();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to decrypt: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _decrypting = false);
      }
    }
  }

  void _refreshFromNotifier() {
    final latest = widget.notifier.findByReportId(_record.reportId);
    if (latest != null) {
      setState(() => _record = latest);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEmergencyAlert = _record.isEmergencyAlert;
    if (!_record.isDecrypted) {
      return _LockedReportView(
        isEmergencyAlert: isEmergencyAlert,
        isDecrypting: _decrypting,
        onDecrypt: _decryptNow,
      );
    }

    final score = _record.avgMoodScore ?? 0;
    final riskCounts = _record.riskFlagCounts ?? const <String, int>{};
    final trend = _record.riskTrend ?? const <int>[];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.55,
      builder: (context, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF7F6F2),
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            children: [
              Text(_record.patientLabel, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(isEmergencyAlert ? 'Emergency alert' : 'Report period', style: Theme.of(context).textTheme.bodySmall),
              Text(_formatDate(_record.receivedAt), style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Mood Overview',
                child: Column(
                  children: [
                    Text(
                      '${(score * 100).round()}%',
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                            color: _scoreColor(context, score),
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(_scoreDescriptor(score), style: Theme.of(context).textTheme.bodyLarge),
                    const SizedBox(height: 12),
                    if (trend.isNotEmpty)
                      _SparklineChart(
                        points: _normalizeTrend(trend),
                        color: Theme.of(context).colorScheme.primary,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Risk Flags',
                child: _RiskSection(riskCounts: riskCounts),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Entry Activity',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total entries: ${_record.entryCount ?? 0}'),
                    const SizedBox(height: 6),
                    Text('Top emotion: ${_record.topEmotion ?? 'Not available'}'),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'AI-assisted summary only. Not a clinical diagnosis.\nRaw journal text is never included in this report.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: () => _editLabel(context),
                child: const Text('Add note / label'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editLabel(BuildContext context) async {
    final controller = TextEditingController(text: _record.patientLabel);
    final newLabel = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit patient label'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Patient label'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (newLabel == null || newLabel.trim().isEmpty) {
      return;
    }

    await widget.notifier.addManualPatientLabel(_record.reportId, newLabel.trim());
    if (!mounted) return;
    _refreshFromNotifier();
  }

  List<double> _normalizeTrend(List<int> trend) {
    final maxValue = trend.isEmpty ? 1 : trend.reduce(math.max);
    final safeMax = maxValue <= 0 ? 1 : maxValue;
    return trend.map((value) => (value / safeMax).clamp(0.0, 1.0)).toList(growable: false);
  }

  String _scoreDescriptor(double score) {
    if (score >= 0.78) return 'Bright and steady';
    if (score >= 0.62) return 'Mostly steady';
    if (score >= 0.46) return 'Mixed';
    if (score >= 0.30) return 'Tender and low';
    return 'Heavy';
  }

  Color _scoreColor(BuildContext context, double score) {
    if (score >= 0.62) return Theme.of(context).colorScheme.primary;
    if (score >= 0.40) return Theme.of(context).colorScheme.secondary;
    return Theme.of(context).colorScheme.error;
  }

  String _formatDate(DateTime date) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class _LockedReportView extends StatelessWidget {
  const _LockedReportView({
    required this.isEmergencyAlert,
    required this.isDecrypting,
    required this.onDecrypt,
  });

  final bool isEmergencyAlert;
  final bool isDecrypting;
  final Future<void> Function() onDecrypt;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 380,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_rounded,
                size: 56,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(height: 12),
              Text(
                isEmergencyAlert ? 'Emergency alert is locked' : 'Report not yet decrypted',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: isDecrypting ? null : onDecrypt,
                child: isDecrypting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Decrypt Now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RiskSection extends StatelessWidget {
  const _RiskSection({required this.riskCounts});

  final Map<String, int> riskCounts;

  @override
  Widget build(BuildContext context) {
    final hasAny = riskCounts.values.any((count) => count > 0);
    if (!hasAny) {
      return Text(
        'No risk flags detected in this report period.',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }

    final entries = riskCounts.entries.toList(growable: false)
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      children: entries
          .map(
            (entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(child: Text(entry.key)),
                  SizedBox(width: 28, child: Text('${entry.value}')),
                  Expanded(
                    flex: 2,
                    child: LinearProgressIndicator(
                      value: (entry.value / 30).clamp(0.0, 1.0),
                      color: entry.value > 2
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.secondary,
                      backgroundColor: const Color(0xFFE0DED7),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F0EB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0DED7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _SparklineChart extends StatelessWidget {
  const _SparklineChart({required this.points, required this.color});

  final List<double> points;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final hasPoints = points.isNotEmpty;
    return SizedBox(
      height: 40,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(
          points: hasPoints ? points : List<double>.filled(7, 0.5),
          color: hasPoints ? color : const Color(0xFFE0DED7),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.points, required this.color});

  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final stepX = points.length == 1 ? 0.0 : size.width / (points.length - 1);
    const padding = 4.0;
    final height = size.height - padding * 2;

    for (var i = 0; i < points.length; i++) {
      final x = stepX * i;
      final y = padding + (1 - points[i].clamp(0.0, 1.0)) * height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.color != color;
  }
}
