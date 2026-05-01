import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/api_endpoint_service.dart';
import '../services/storage_service.dart';

class UnstuckScreen extends StatefulWidget {
  const UnstuckScreen({
    super.key,
    required this.onGoToJournal,
  });

  final VoidCallback onGoToJournal;

  @override
  State<UnstuckScreen> createState() => _UnstuckScreenState();
}

class _UnstuckScreenState extends State<UnstuckScreen> {
  static const int _exerciseSeconds = 60;
  static const int _inhaleSeconds = 4;
  static const int _holdSeconds = 4;
  static const int _exhaleSeconds = 6;

  Timer? _timer;
  int _remainingSeconds = _exerciseSeconds;
  bool _isRunning = false;

  int _groundingStep = 0;
  final List<bool> _groundingChecks = List<bool>.filled(5, false);

  final List<_UnstuckPrompt> _prompts = const [
    _UnstuckPrompt(
      title: 'Name the knot',
      body: 'What thought is looping in your head right now?',
    ),
    _UnstuckPrompt(
      title: 'Shrink the horizon',
      body: 'What is one thing you can do in the next 10 minutes?',
    ),
    _UnstuckPrompt(
      title: 'Gentle reframe',
      body: 'If a friend felt this, what would you tell them?',
    ),
    _UnstuckPrompt(
      title: 'Body check-in',
      body: 'Where in your body do you feel this most strongly?',
    ),
  ];

  int _promptIndex = 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggleBreathing() {
    if (_isRunning) {
      _timer?.cancel();
      setState(() => _isRunning = false);
      return;
    }

    if (_remainingSeconds <= 0) {
      _remainingSeconds = _exerciseSeconds;
    }

    setState(() => _isRunning = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_remainingSeconds <= 1) {
        timer.cancel();
        setState(() {
          _remainingSeconds = 0;
          _isRunning = false;
        });
        return;
      }
      setState(() => _remainingSeconds -= 1);
    });
  }

  void _resetBreathing() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _remainingSeconds = _exerciseSeconds;
    });
  }

  String _breathingInstruction() {
    final elapsed = _exerciseSeconds - _remainingSeconds;
    final cycleLength = _inhaleSeconds + _holdSeconds + _exhaleSeconds;
    final phaseTick = elapsed % cycleLength;

    if (phaseTick < _inhaleSeconds) {
      return 'Inhale';
    }
    if (phaseTick < _inhaleSeconds + _holdSeconds) {
      return 'Hold';
    }
    return 'Exhale';
  }

  void _nextPrompt() {
    setState(() {
      _promptIndex = (_promptIndex + 1) % _prompts.length;
    });
  }

  void _toggleGrounding(int index) {
    setState(() {
      _groundingChecks[index] = !_groundingChecks[index];
      final completedCount = _groundingChecks.where((checked) => checked).length;
      if (completedCount == 0) {
        _groundingStep = 0;
      } else if (completedCount == _groundingChecks.length) {
        _groundingStep = _groundingChecks.length;
      } else {
        _groundingStep = completedCount;
      }
    });
  }

  Future<void> _completeSession() async {
    final elapsed = _exerciseSeconds - _remainingSeconds;
    final groundingCompleted = _groundingChecks.every((v) => v);
    final activePrompt = _prompts[_promptIndex];

    final session = {
      'timestamp': DateTime.now().toIso8601String(),
      'duration_seconds': elapsed,
      'grounding_completed': groundingCompleted,
      'prompt_title': activePrompt.title,
      'prompt_body': activePrompt.body,
    };

    try {
      await StorageService.instance.addUnstuckSession(session);
    } catch (e) {
      // ignore storage failures gracefully
    }

    final optIn = StorageService.instance.readBoolSetting('setting_clinician_opt_in', fallback: false);
    if (optIn) {
      try {
        final uri = ApiEndpointService.instance.buildUri('/clinician/signal');
        await ApiEndpointService.instance.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'event': 'unstuck_session', 'session': session}),
        );
      } catch (_) {
        // best-effort send; ignore failures
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Session saved.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (_exerciseSeconds - _remainingSeconds) / _exerciseSeconds;
    final activePrompt = _prompts[_promptIndex];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Unstuck', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 6),
              Text(
                'Use a short reset, grounding, and one tiny next step.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              _Panel(
                title: '60-second reset',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(999),
                      color: theme.colorScheme.primary,
                      backgroundColor: const Color(0xFFE2DFD8),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          _remainingSeconds == 0
                              ? 'Complete'
                              : '$_remainingSeconds s',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F1EC),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(_breathingInstruction()),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: _toggleBreathing,
                          icon: Icon(
                            _isRunning
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                          label: Text(_isRunning ? 'Pause' : 'Start'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _resetBreathing,
                          icon: const Icon(Icons.replay_rounded),
                          label: const Text('Reset'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _Panel(
                title: '5-4-3-2-1 grounding',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _groundingHeadline(),
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 10),
                    ...List.generate(_groundingChecks.length, (index) {
                      return CheckboxListTile(
                        value: _groundingChecks[index],
                        onChanged: (_) => _toggleGrounding(index),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(_groundingPromptAt(index)),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _Panel(
                title: 'Unblock prompt',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activePrompt.title,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(activePrompt.body, style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: widget.onGoToJournal,
                          icon: const Icon(Icons.edit_note_rounded),
                          label: const Text('Write this in Journal'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _nextPrompt,
                          icon: const Icon(Icons.shuffle_rounded),
                          label: const Text('Another prompt'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
                const SizedBox(height: 12),
                Center(
                  child: FilledButton.icon(
                    onPressed: _completeSession,
                    icon: const Icon(Icons.check_circle_rounded),
                    label: const Text('Mark session complete'),
                  ),
                ),
              const SizedBox(height: 14),
              Card(
                color: const Color(0xFFFFF3F0),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.health_and_safety_rounded, color: Color(0xFFB8523A)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'If you may hurt yourself or someone else, call local emergency services immediately.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _groundingHeadline() {
    if (_groundingStep >= _groundingChecks.length) {
      return 'Grounding complete. Notice any shift, even a small one.';
    }
    return 'Complete each anchor at your own pace.';
  }

  String _groundingPromptAt(int index) {
    switch (index) {
      case 0:
        return '5 things you can see';
      case 1:
        return '4 things you can feel';
      case 2:
        return '3 things you can hear';
      case 3:
        return '2 things you can smell';
      default:
        return '1 thing you can taste';
    }
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F0EB),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _UnstuckPrompt {
  const _UnstuckPrompt({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;
}
