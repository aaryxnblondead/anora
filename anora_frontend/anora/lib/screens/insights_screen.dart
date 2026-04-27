import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/journal_entry.dart';
import '../services/storage_service.dart';

final _journalEntriesProvider = StreamProvider<List<JournalEntry>>((ref) {
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

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(_journalEntriesProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: entriesAsync.when(
          data: (entries) => _InsightsContent(entries: entries),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Text('Could not load insights: $error'),
          ),
        ),
      ),
    );
  }
}

class _InsightsContent extends StatelessWidget {
  const _InsightsContent({required this.entries});

  final List<JournalEntry> entries;

  @override
  Widget build(BuildContext context) {
    final recentEntries = entries.take(10).toList();
    final trendPoints = _buildTrendPoints(entries);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Insights', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
          'Your last seven days, at a glance.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        _MoodTrendCard(points: trendPoints),
        const SizedBox(height: 20),
        Text('Recent entries', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Expanded(
          child: recentEntries.isEmpty
              ? const _EmptyStateCard()
              : ListView.separated(
                  itemCount: recentEntries.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    return _EntryTile(entry: recentEntries[index]);
                  },
                ),
        ),
      ],
    );
  }

  List<_MoodPoint> _buildTrendPoints(List<JournalEntry> entries) {
    final now = DateTime.now();
    final lastSevenDays = List.generate(7, (index) {
      final day = now.subtract(Duration(days: 6 - index));
      return DateTime(day.year, day.month, day.day);
    });

    return lastSevenDays.map((day) {
      final dayEntries = entries.where((entry) {
        final timestamp = entry.timestamp;
        return timestamp.year == day.year &&
            timestamp.month == day.month &&
            timestamp.day == day.day;
      });

      if (dayEntries.isEmpty) {
        return _MoodPoint(
          dayLabel: _formatDay(day),
          moodScore: 0.5,
          hasData: false,
        );
      }

      final average = dayEntries
              .map((entry) => entry.moodScore)
              .reduce((a, b) => a + b) /
          dayEntries.length;

      return _MoodPoint(
        dayLabel: _formatDay(day),
        moodScore: average,
        hasData: true,
      );
    }).toList();
  }

  String _formatDay(DateTime date) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[date.weekday - 1];
  }
}

class _MoodTrendCard extends StatelessWidget {
  const _MoodTrendCard({required this.points});

  final List<_MoodPoint> points;

  @override
  Widget build(BuildContext context) {
    final lineColor = Theme.of(context).colorScheme.secondary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F0EB),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mood trend', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: _buildChart(context, lineColor),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(BuildContext context, Color lineColor) {
    final spots = points.asMap().entries
        .map(
          (entry) => FlSpot(
            entry.key.toDouble(),
            entry.value.moodScore,
          ),
        )
        .toList(growable: false);

    if (!points.any((p) => p.hasData)) {
      return Center(
        child: Text(
          'No mood data yet',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: points.length - 1,
        minY: 0,
        maxY: 1,
        gridData: FlGridData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: lineColor,
            barWidth: 2.5,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                final point = points[index];
                if (!point.hasData) {
                  return FlDotCirclePainter(
                    radius: 3,
                    color: Colors.transparent,
                    strokeWidth: 1.5,
                    strokeColor: const Color(0xFFCCC8C0),
                  );
                }
                return FlDotCirclePainter(
                  radius: 5,
                  color: lineColor,
                  strokeWidth: 1.5,
                  strokeColor: Colors.white,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              color: lineColor.withValues(alpha: 0.10),
            ),
          ),
        ],
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (value, _) {
                final index = value.toInt();
                if (index < 0 || index >= points.length) {
                  return const SizedBox.shrink();
                }
                final point = points[index];
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    point.dayLabel,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryTile extends StatefulWidget {
  const _EntryTile({required this.entry});

  final JournalEntry entry;

  @override
  State<_EntryTile> createState() => _EntryTileState();
}

class _EntryTileState extends State<_EntryTile> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final mood = _formatMood(widget.entry);
    final date = _formatDate(widget.entry.timestamp);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() => _revealed = !_revealed),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0DED7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(date, style: Theme.of(context).textTheme.bodyMedium),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .secondary
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    mood,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _revealed ? widget.entry.text : '••••••••••••••••••••••••',
              maxLines: _revealed ? 4 : 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime timestamp) {
    final month = _monthLabel(timestamp.month);
    return '$month ${timestamp.day}';
  }

  String _monthLabel(int month) {
    const labels = [
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
    return labels[month - 1];
  }

  String _formatMood(JournalEntry entry) {
    if (entry.moodPath.isNotEmpty) {
      return entry.moodPath.last;
    }

    final score = entry.moodScore;
    if (score >= 0.8) return 'Bright';
    if (score >= 0.6) return 'Good';
    if (score >= 0.4) return 'Steady';
    if (score >= 0.2) return 'Low';
    return 'Rough';
  }
}

class _MoodPoint {
  const _MoodPoint({
    required this.dayLabel,
    required this.moodScore,
    required this.hasData,
  });

  final String dayLabel;
  final double moodScore;
  final bool hasData;
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F0EB),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.self_improvement_rounded,
                size: 30,
                color: Color(0xFF5B6F8F),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'No entries yet',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'As you write, your mood trends will appear here.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
