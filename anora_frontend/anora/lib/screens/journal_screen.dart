import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/journal_entry.dart';
import '../services/ai_inference_service.dart';
import '../services/secure_link_service.dart';
import '../services/storage_service.dart';
import '../state/settings_controller.dart';
import '../state/navigation_state.dart';
import '../widgets/feelings_wheel.dart';

final _moodPathProvider = StateProvider<List<String>>((ref) => []);
final _moodScoreProvider = StateProvider<double>(
  (ref) => FeelingsWheelData.moodScoreForPath(const []),
);

class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _textFieldKey = GlobalKey();

  bool _isSaving = false;
  String? _lastDominantEmotion;
  JournalEntry? _lastSavedEntry;

  Timer? _debounce;
  bool _isAiAnalyzingLive = false;
  bool _hasTriggeredCrisisModal = false;

  static const Set<String> _criticalRiskAliases = <String>{
    'risk_selfharm',
    'risk_depression',
    'risk_mania',
    'self-harm',
    'depression',
    'mania',
  };

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
    }

    if (_controller.text.trim().isEmpty) {
      if (mounted) {
        setState(() => _isAiAnalyzingLive = false);
      }
      return;
    }

    if (mounted) {
      setState(() => _isAiAnalyzingLive = true);
    }

    final wordCount = _controller.text.trim().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;
    if (wordCount < 5) {
      setState(() => _isAiAnalyzingLive = false);
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 1800), () async {
      final text = _controller.text.trim();
      if (text.isEmpty) return;

      try {
        final aiResult = await AiInferenceService.instance.analyze(text);

        if (!mounted) return;
        setState(() {
          _isAiAnalyzingLive = false;
          if (ref.read(_moodPathProvider).length <= 1) {
            _lastDominantEmotion = aiResult.dominantEmotion;
          }
        });

        await _checkCrisisProtocol(
          text: text,
          riskFlags: aiResult.riskFlags,
          sentimentScore: aiResult.sentimentScore,
        );
      } catch (_) {
        if (mounted) {
          setState(() => _isAiAnalyzingLive = false);
        }
      }
    });
  }

  Future<void> _checkCrisisProtocol({
    required String text,
    required List<String> riskFlags,
    required double sentimentScore,
  }) async {
    if (_hasTriggeredCrisisModal) return;

    final hasCriticalPhrase = _containsCriticalSelfHarmPhrase(text);
    final normalizedFlags = riskFlags.map((flag) => flag.toLowerCase()).toSet();
    final criticalFlagCount = normalizedFlags.where(_criticalRiskAliases.contains).length;
    final lowSafetyScore = sentimentScore < 0.35;
    final isCritical = hasCriticalPhrase || lowSafetyScore || criticalFlagCount >= 1;
    if (!isCritical) return;

    _hasTriggeredCrisisModal = true;
    _focusNode.unfocus();

    await SecureLinkService.instance.sendEmergencyAlert(
      triggerText: text,
      riskFlags: riskFlags,
      source: 'journal_live_typing',
    );

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.health_and_safety, color: Colors.redAccent),
            SizedBox(width: 8),
            Expanded(child: Text('We are here for you')),
          ],
        ),
        content: const Text(
          'Your writing indicates you might be in distress. You are not alone, and help is available right now.',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Future<void>.delayed(const Duration(minutes: 5), () {
                _hasTriggeredCrisisModal = false;
              });
            },
            child: const Text(
              "I'm safe, continue journaling",
              style: TextStyle(color: Colors.grey),
            ),
          ),
          FilledButton.icon(
            onPressed: () async {
              final uri = Uri(scheme: 'tel', path: '988');
              await launchUrl(uri);
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
            },
            icon: const Icon(Icons.phone),
            label: const Text('Call 988'),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
          ),
        ],
      ),
    );
  }

  void _scrollToComposer() {
    final context = _textFieldKey.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: 0.2,
    );
  }

  Future<void> _saveEntry() async {
    if (_isSaving) return;

    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Write a few words first.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final moodScore = ref.read(_moodScoreProvider);
      final moodPath = ref.read(_moodPathProvider);
      final settings = ref.read(settingsControllerProvider);

      final aiResult = await AiInferenceService.instance.analyze(text);
      final blendedMoodScore = _deriveSafetyFirstMoodScore(
        wheelMoodScore: moodScore,
        text: text,
        aiResult: aiResult,
        moodPath: moodPath,
      );

      final entry = JournalEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        text: text,
        timestamp: DateTime.now(),
        moodScore: blendedMoodScore,
        moodPath: moodPath,
        riskFlags: aiResult.riskFlags,
      );

      await StorageService.instance.journalBox.add(entry);
      await SecureLinkService.instance.syncMoodTelemetry(entry: entry);
      await _checkCrisisProtocol(
        text: text,
        riskFlags: aiResult.riskFlags,
        sentimentScore: aiResult.sentimentScore,
      );

      // If user enabled automatic Unstuck launches and this entry indicates
      // moderate distress (not critical), open the Unstuck flow.
      try {
        final settings = ref.read(settingsControllerProvider);
        final isModerate = blendedMoodScore < 0.45 && blendedMoodScore >= 0.2;
        if (settings.autoUnstuckEnabled && isModerate) {
          ref.read(navRequestProvider.notifier).state = 1; // Unstuck tab index
        }
      } catch (_) {}

      if (settings.hapticsEnabled) {
        await HapticFeedback.mediumImpact();
      }

      if (mounted) {
        setState(() {
          _lastSavedEntry = entry;
          if (moodPath.length <= 1) {
            _lastDominantEmotion = aiResult.dominantEmotion;
          }
        });
      }

      _controller.clear();
      _focusNode.unfocus();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved to your secure vault.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not analyze entry: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  double _deriveSafetyFirstMoodScore({
    required double wheelMoodScore,
    required String text,
    required AiInferenceResult aiResult,
    required List<String> moodPath,
  }) {
    final hasDetailedWheelSelection = moodPath.length >= 2;
    
    double blended;
    if (hasDetailedWheelSelection) {
      blended = (wheelMoodScore * 0.75) + (aiResult.sentimentScore * 0.25);
    } else if (moodPath.length == 1) {
      blended = (wheelMoodScore * 0.60) + (aiResult.sentimentScore * 0.40);
    } else {
      blended = aiResult.sentimentScore;
    }

    final hasCriticalPhrase = _containsCriticalSelfHarmPhrase(text);
    if (hasCriticalPhrase) {
      return blended.clamp(0.0, 0.20);
    }

    return blended.clamp(0.0, 1.0);
  }

  bool _containsCriticalSelfHarmPhrase(String text) {
    final lowerText = text.toLowerCase();
    return lowerText.contains('killing myself') ||
      lowerText.contains('feel like dying') ||
        lowerText.contains('end my life') ||
        lowerText.contains('suicide') ||
        lowerText.contains('want to die') ||
      lowerText.contains('better off dead') ||
      lowerText.contains('kill myself') ||
        lowerText.contains('ready to die') ||
        lowerText.contains('hurt myself');
  }

  Future<void> _shareLastEntryContent() async {
    final entry = _lastSavedEntry;
    if (entry == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final success = await SecureLinkService.instance.shareEntryContent(entry: entry);

    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Entry content shared through your private connection.'
              : 'Connect to a clinician first in Settings to share entry content.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final moodPath = ref.watch(_moodPathProvider);
    final selectedFeeling = moodPath.isNotEmpty ? moodPath.last : null;
    final shouldPrompt = selectedFeeling != null && selectedFeeling.isNotEmpty;
    final viewInsets = MediaQuery.of(context).viewInsets;

    return SafeArea(
      child: AnimatedPadding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, 12 + viewInsets.bottom),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: SingleChildScrollView(
          controller: _scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FeelingsWheel(
                initialPath: moodPath,
                onFeelingSelected: (path) {
                  ref.read(_moodPathProvider.notifier).state = path;
                  ref.read(_moodScoreProvider.notifier).state =
                      FeelingsWheelData.moodScoreForPath(path);
                  setState(() => _lastDominantEmotion = null);
                  if (settings.hapticsEnabled) {
                    HapticFeedback.selectionClick();
                  }
                },
              ),
              const SizedBox(height: 10),
              if (!shouldPrompt)
                Text(
                  'Tap a core feeling to continue',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFB0A898),
                      ),
                ),
              const SizedBox(height: 18),
              if (shouldPrompt)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Why do you feel $selectedFeeling?',
                        style: Theme.of(context).textTheme.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Tooltip(
                      message: 'On-device AI is analyzing text locally for your privacy.',
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _isAiAnalyzingLive
                              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isAiAnalyzingLive) ...[
                              SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ] else ...[
                              Icon(Icons.memory, size: 14, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              _isAiAnalyzingLive ? 'Analyzing...' : 'Edge AI Active',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _isAiAnalyzingLive
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              if (shouldPrompt) const SizedBox(height: 12),
              if (shouldPrompt && _lastDominantEmotion != null && moodPath.length <= 1) ...[
                Chip(
                  avatar: const Icon(Icons.auto_awesome, size: 16),
                  label: Text('Model suggests $_lastDominantEmotion'),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                key: _textFieldKey,
                controller: _controller,
                focusNode: _focusNode,
                minLines: 6,
                maxLines: 12,
                textInputAction: TextInputAction.newline,
                onTap: _scrollToComposer,
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
                onEditingComplete: _scrollToComposer,
                decoration: InputDecoration(
                  hintText: shouldPrompt ? 'Write a few words...' : 'Select a feeling to begin.',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSaving || !shouldPrompt ? null : _saveEntry,
                  child: _isSaving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save to Secure Vault'),
                ),
              ),
              if (_lastSavedEntry != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _shareLastEntryContent,
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('Share Entry Content'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
