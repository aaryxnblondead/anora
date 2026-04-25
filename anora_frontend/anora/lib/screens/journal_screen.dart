import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/journal_entry.dart';
import '../services/ai_inference_service.dart';
import '../services/storage_service.dart';
import '../state/settings_controller.dart';
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

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
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
      final blendedMoodScore = (
        (moodScore * 0.6) + (aiResult.sentimentScore * 0.4)
      ).clamp(0.0, 1.0);
      final entry = JournalEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        text: text,
        timestamp: DateTime.now(),
        moodScore: blendedMoodScore,
        moodPath: moodPath,
        riskFlags: aiResult.riskFlags,
      );

      await StorageService.instance.journalBox.add(entry);
      if (settings.hapticsEnabled) {
        await HapticFeedback.mediumImpact();
      }

      if (mounted) {
        setState(() {
          _lastDominantEmotion = moodPath.length <= 1 ? aiResult.dominantEmotion : null;
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
                Text(
                  'Why do you feel $selectedFeeling?',
                  style: Theme.of(context).textTheme.titleLarge,
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
                  hintText: shouldPrompt
                      ? 'Write a few words...'
                      : 'Select a feeling to begin.',
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
            ],
          ),
        ),
      ),
    );
  }
}

