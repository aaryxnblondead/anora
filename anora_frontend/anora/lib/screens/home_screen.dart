import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/journal_entry.dart';
import '../utils/env.dart';
import '../services/storage_service.dart';
import '../widgets/journal_mascot.dart';

final _homeEntriesProvider = StreamProvider<List<JournalEntry>>((ref) {
  final box = StorageService.instance.journalBox;

  Stream<List<JournalEntry>> entriesStream() async* {
    final initial = box.values.toList();
    initial.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    yield initial;

    await for (final _ in box.watch()) {
      final entries = box.values.toList();
      entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      yield entries;
    }
  }

  return entriesStream();
});

final _quoteStateProvider = StateNotifierProvider<_QuoteStateController, _QuoteState>(
  (ref) => _QuoteStateController(),
);

class _QuoteState {
  const _QuoteState({
    this.quotes = const [],
    this.index = 0,
    this.isLoaded = false,
  });

  final List<_QuoteRecord> quotes;
  final int index;
  final bool isLoaded;

  _QuoteState copyWith({
    List<_QuoteRecord>? quotes,
    int? index,
    bool? isLoaded,
  }) {
    return _QuoteState(
      quotes: quotes ?? this.quotes,
      index: index ?? this.index,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }
}

class _QuoteStateController extends StateNotifier<_QuoteState> {
  _QuoteStateController() : super(const _QuoteState()) {
    _load();
  }

  Future<void> _load() async {
    final rawQuotes = await StorageService.instance.loadQuotes();
    final quotes = rawQuotes.map(_QuoteRecord.fromMap).toList();
    final index = await StorageService.instance.loadQuoteIndex();
    final safeIndex = quotes.isEmpty ? 0 : index % quotes.length;
    state = state.copyWith(
      quotes: quotes,
      index: safeIndex,
      isLoaded: true,
    );
  }

  Future<void> nextQuote() async {
    if (state.quotes.isEmpty) return;
    final next = (state.index + 1) % state.quotes.length;
    state = state.copyWith(index: next);
    await StorageService.instance.saveQuoteIndex(next);
  }

  Future<void> toggleFavorite(String id) async {
    final updated = state.quotes
        .map((quote) => quote.id == id
            ? quote.copyWith(isFavorite: !quote.isFavorite)
            : quote)
        .toList();
    state = state.copyWith(quotes: updated);
    await StorageService.instance.saveQuotes(
      updated.map((quote) => quote.toMap()).toList(),
    );
  }
}

class _QuoteRecord {
  const _QuoteRecord({
    required this.id,
    required this.text,
    required this.author,
    required this.isFavorite,
  });

  final String id;
  final String text;
  final String author;
  final bool isFavorite;

  _QuoteRecord copyWith({bool? isFavorite}) {
    return _QuoteRecord(
      id: id,
      text: text,
      author: author,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'text': text,
      'author': author,
      'isFavorite': isFavorite,
    };
  }

  static _QuoteRecord fromMap(Map<String, dynamic> map) {
    return _QuoteRecord(
      id: map['id']?.toString() ?? '',
      text: map['text']?.toString() ?? '',
      author: map['author']?.toString() ?? 'Anora',
      isFavorite: map['isFavorite'] == true,
    );
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, required this.onGoToJournal});

  final VoidCallback onGoToJournal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(_homeEntriesProvider);
    final quoteState = ref.watch(_quoteStateProvider);
    final quoteController = ref.read(_quoteStateProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: entriesAsync.when(
          data: (entries) => _HomeContent(
            entries: entries,
            onGoToJournal: onGoToJournal,
            quoteState: quoteState,
            onNextQuote: quoteController.nextQuote,
            onToggleFavorite: quoteController.toggleFavorite,
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Text('Could not load your home view: $error'),
          ),
        ),
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({
    required this.entries,
    required this.onGoToJournal,
    required this.quoteState,
    required this.onNextQuote,
    required this.onToggleFavorite,
  });

  final List<JournalEntry> entries;
  final VoidCallback onGoToJournal;
  final _QuoteState quoteState;
  final VoidCallback onNextQuote;
  final ValueChanged<String> onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final summary = _buildMoodSummary(entries);
    final sparklinePoints = _buildSparkline(entries);
    final recentMood = entries.isNotEmpty
      ? List<String>.from(entries.first.moodPath)
      : const <String>[];
    final quote = _currentQuote(quoteState);
    final mascotMood = _mascotMoodFor(recentMood);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Home', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(
            'A gentle snapshot of your recent mood.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _MascotPanel(mood: mascotMood),
          const SizedBox(height: 16),
          _MoodSummaryCard(
            summary: summary,
            recentMood: recentMood,
            sparklinePoints: sparklinePoints,
          ),
          const SizedBox(height: 16),
          _QuoteCard(
            quote: quote,
            isLoading: !quoteState.isLoaded,
            onNextQuote: onNextQuote,
            onToggleFavorite: onToggleFavorite,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onGoToJournal,
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('Go to Journal'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'If you are in immediate danger, please call your local emergency number.',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.emergency_rounded),
              label: const Text('I need immediate help / emergency'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                try {
                  final response = await http.get(Uri.parse('${Env.apiBaseUrl}/health'));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        response.statusCode == 200
                            ? 'Backend reachable through AWS deployment.'
                            : 'Backend ping returned HTTP ${response.statusCode}.',
                      ),
                    ),
                  );
                } catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not reach backend: $error')),
                  );
                }
              },
              icon: const Icon(Icons.cloud_sync_rounded),
              label: const Text('Send a ping'),
            ),
          ),
        ],
      ),
    );
  }

  _QuoteRecord? _currentQuote(_QuoteState quoteState) {
    if (quoteState.quotes.isEmpty) return null;
    final index = quoteState.index % quoteState.quotes.length;
    return quoteState.quotes[index];
  }

  MascotMood _mascotMoodFor(List<String> moodPath) {
    if (moodPath.isEmpty) return MascotMood.idle;
    switch (moodPath.first.toLowerCase()) {
      case 'happy':
        return MascotMood.happy;
      case 'sad':
        return MascotMood.sad;
      case 'angry':
        return MascotMood.angry;
      case 'fearful':
        return MascotMood.fearful;
      case 'disgusted':
        return MascotMood.disgusted;
      case 'surprised':
        return MascotMood.surprised;
      case 'bad':
        return MascotMood.thinking;
    }
    return MascotMood.idle;
  }

  _MoodSummary _buildMoodSummary(List<JournalEntry> entries) {
    if (entries.isEmpty) {
      return const _MoodSummary(
        average: 0.5,
        entryCount: 0,
        descriptor: 'No entries yet',
        detail: 'Start your first check-in today.',
      );
    }

    final now = DateTime.now();
    final lastSevenDays = entries.where((entry) {
      return now.difference(entry.timestamp).inDays <= 6;
    }).toList();

    final source = lastSevenDays.isNotEmpty ? lastSevenDays : entries;
    final average = source
            .map((entry) => entry.moodScore)
            .reduce((a, b) => a + b) /
        source.length;

    final descriptor = _descriptorFor(average);
    final detail = lastSevenDays.isNotEmpty
        ? 'Based on ${source.length} check-ins this week.'
        : 'Based on your recent check-ins.';

    return _MoodSummary(
      average: average,
      entryCount: source.length,
      descriptor: descriptor,
      detail: detail,
    );
  }

  String _descriptorFor(double score) {
    if (score >= 0.78) return 'Bright and steady';
    if (score >= 0.62) return 'Mostly steady';
    if (score >= 0.46) return 'Mixed but manageable';
    if (score >= 0.3) return 'Tender and low';
    return 'Heavy right now';
  }

  List<double> _buildSparkline(List<JournalEntry> entries) {
    if (entries.isEmpty) return [];

    final now = DateTime.now();
    final days = List.generate(7, (index) {
      final day = now.subtract(Duration(days: 6 - index));
      return DateTime(day.year, day.month, day.day);
    });

    return days.map((day) {
      final dayEntries = entries.where((entry) {
        final timestamp = entry.timestamp;
        return timestamp.year == day.year &&
            timestamp.month == day.month &&
            timestamp.day == day.day;
      }).toList();

      if (dayEntries.isEmpty) return 0.5;
      final average = dayEntries
              .map((entry) => entry.moodScore)
              .reduce((a, b) => a + b) /
          dayEntries.length;
      return average;
    }).toList();
  }
}

class _MoodSummary {
  const _MoodSummary({
    required this.average,
    required this.entryCount,
    required this.descriptor,
    required this.detail,
  });

  final double average;
  final int entryCount;
  final String descriptor;
  final String detail;
}

class _MoodSummaryCard extends StatelessWidget {
  const _MoodSummaryCard({
    required this.summary,
    required this.recentMood,
    required this.sparklinePoints,
  });

  final _MoodSummary summary;
  final List<String> recentMood;
  final List<double> sparklinePoints;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final moodText = recentMood.isNotEmpty
      ? recentMood.join(' - ')
      : 'No mood selected yet';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F0EB),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mood lately', style: theme.textTheme.titleLarge),
          if (summary.entryCount == 0) ...[
            const SizedBox(height: 12),
            const _EmptyStateIllustration(),
          ],
          const SizedBox(height: 10),
          Text(
            summary.descriptor,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            summary.detail,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          _SparklineChart(
            points: sparklinePoints,
            color: accent,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatPill(label: 'Avg', value: '${(summary.average * 100).round()}%'),
              const SizedBox(width: 8),
              _StatPill(label: 'Entries', value: '${summary.entryCount}'),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Most recent mood',
            style: theme.textTheme.labelLarge?.copyWith(
              color: const Color(0xFF6E7A73),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            moodText,
            style: theme.textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE0DED7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: const Color(0xFF6E7A73),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ],
      ),
    );
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({
    required this.quote,
    required this.isLoading,
    required this.onNextQuote,
    required this.onToggleFavorite,
  });

  final _QuoteRecord? quote;
  final bool isLoading;
  final VoidCallback onNextQuote;
  final ValueChanged<String> onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE0DED7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Today\'s note', style: theme.textTheme.titleLarge),
              if (quote != null)
                IconButton(
                  onPressed: () => onToggleFavorite(quote!.id),
                  icon: Icon(
                    quote!.isFavorite
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: const Color(0xFFE0A72B),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            isLoading
                ? 'Loading your quotes...'
                : quote != null
                    ? '"${quote!.text}"'
                    : 'Add a quote to get started.',
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                quote != null ? '- ${quote!.author}' : '',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6E7A73),
                ),
              ),
              TextButton(
                onPressed: quote != null ? onNextQuote : null,
                child: const Text('Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MascotPanel extends StatefulWidget {
  const _MascotPanel({required this.mood});

  final MascotMood mood;

  @override
  State<_MascotPanel> createState() => _MascotPanelState();
}

class _MascotPanelState extends State<_MascotPanel> {
  MascotMood? _overrideMood;

  @override
  Widget build(BuildContext context) {
    final mood = _overrideMood ?? widget.mood;
    final cfg = kMoodConfigs[mood] ?? kMoodConfigs[MascotMood.idle]!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE0DED7)),
      ),
      child: Column(
        children: [
          MascotSpeechBubble(
            message: cfg.message,
            accentColor: cfg.accentColor,
          ),
          const SizedBox(height: 8),
          JournalMascot(
            mood: mood,
            size: 150,
            onTap: () {
              setState(() => _overrideMood = MascotMood.thinking);
              Future.delayed(const Duration(seconds: 2), () {
                if (!mounted) return;
                setState(() => _overrideMood = null);
              });
            },
          ),
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
      height: 38,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(
          points: hasPoints ? points : List.filled(7, 0.5),
          color: hasPoints ? color : const Color(0xFFB8B1A7),
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

class _EmptyStateIllustration extends StatelessWidget {
  const _EmptyStateIllustration();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0DED7)),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: Color(0xFFF1F0EB),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.self_improvement_rounded,
              color: Color(0xFF87958B),
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No check-ins yet',
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your first entry will light up this space.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF6E7A73),
            ),
          ),
        ],
      ),
    );
  }
}
