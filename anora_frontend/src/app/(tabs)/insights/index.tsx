import React, { useEffect, useMemo, useState } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import ScreenWrapper from '../../../components/ScreenWrapper';
import { getEntries, JournalEntry } from '../../../state/journal';
import { runLocalInference } from '../../../services/ai';

export default function InsightsScreen() {
  const [entries, setEntries] = useState<JournalEntry[]>([]);

  useEffect(() => {
    const load = async () => {
      const stored = await getEntries();
      setEntries(stored);
    };
    load();
  }, []);

  const stats = useMemo(() => {
    const total = entries.length;
    const last = entries[0];
    const moodCounts = entries.reduce<Record<string, number>>((acc, entry) => {
      acc[entry.mood] = (acc[entry.mood] || 0) + 1;
      return acc;
    }, {});
    const riskCounts = entries.reduce<Record<string, number>>((acc, entry) => {
      const inference = runLocalInference(entry.text);
      inference.riskFlags.forEach((flag) => {
        acc[flag] = (acc[flag] || 0) + 1;
      });
      return acc;
    }, {} as Record<string, number>);
    const topMood = Object.entries(moodCounts).sort((a, b) => b[1] - a[1])[0]?.[0];
    const topRisk = Object.entries(riskCounts).sort((a, b) => b[1] - a[1])[0]?.[0];
    return { total, last, moodCounts, topMood, riskCounts, topRisk };
  }, [entries]);

  return (
    <ScreenWrapper>
      <View style={styles.header}>
        <Text style={styles.title}>Insights</Text>
        <Text style={styles.subtitle}>Quick view of your recent mood and journaling.</Text>
      </View>

      <View style={styles.cardsRow}>
        <View style={styles.card}>
          <Text style={styles.cardLabel}>Entries</Text>
          <Text style={styles.cardValue}>{stats.total}</Text>
          <Text style={styles.cardHint}>Total saved</Text>
        </View>
        <View style={styles.card}>
          <Text style={styles.cardLabel}>Top mood</Text>
          <Text style={styles.cardValue}>{stats.topMood ?? '—'}</Text>
          <Text style={styles.cardHint}>Most frequent</Text>
        </View>
        <View style={styles.card}>
          <Text style={styles.cardLabel}>Risk flag</Text>
          <Text style={styles.cardValue}>{stats.topRisk ?? '—'}</Text>
          <Text style={styles.cardHint}>Most detected</Text>
        </View>
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Recent entry</Text>
        {stats.last ? (
          <View style={styles.recentCard}>
            <Text style={styles.recentMood}>{stats.last.mood}</Text>
            <Text style={styles.recentDate}>{new Date(stats.last.createdAt).toLocaleString()}</Text>
            <Text style={styles.recentText}>{stats.last.text}</Text>
          </View>
        ) : (
          <Text style={styles.empty}>Write your first entry to see insights.</Text>
        )}
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Mood tally</Text>
        {entries.length === 0 ? (
          <Text style={styles.empty}>No data yet.</Text>
        ) : (
          <View style={{ gap: 8 }}>
            {Object.entries(stats.moodCounts).map(([mood, count]) => (
              <View key={mood} style={styles.moodRow}>
                <Text style={styles.moodLabel}>{mood}</Text>
                <Text style={styles.moodCount}>{count}</Text>
              </View>
            ))}
          </View>
        )}
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Risk tally</Text>
        {entries.length === 0 ? (
          <Text style={styles.empty}>No data yet.</Text>
        ) : (
          <View style={{ gap: 8 }}>
            {Object.entries(stats.riskCounts ?? {}).map(([flag, count]) => (
              <View key={flag} style={styles.moodRow}>
                <Text style={styles.moodLabel}>{flag}</Text>
                <Text style={styles.moodCount}>{count}</Text>
              </View>
            ))}
            {Object.keys(stats.riskCounts ?? {}).length === 0 && (
              <Text style={styles.empty}>No risk flags detected.</Text>
            )}
          </View>
        )}
      </View>
    </ScreenWrapper>
  );
}

const styles = StyleSheet.create({
  header: { gap: 6, marginBottom: 16 },
  title: { fontSize: 28, fontWeight: '700', color: '#0F172A' },
  subtitle: { color: '#475569' },
  cardsRow: { flexDirection: 'row', gap: 12, marginBottom: 16 },
  card: {
    flex: 1,
    backgroundColor: '#fff',
    borderRadius: 16,
    padding: 16,
    borderWidth: 1,
    borderColor: '#E2E8F0',
    gap: 4,
  },
  cardLabel: { color: '#6366F1', fontWeight: '600' },
  cardValue: { fontSize: 24, fontWeight: '700', color: '#0F172A' },
  cardHint: { color: '#94A3B8' },
  section: { marginTop: 12, gap: 8 },
  sectionTitle: { fontWeight: '700', fontSize: 18, color: '#0F172A' },
  recentCard: {
    backgroundColor: '#fff',
    borderRadius: 16,
    padding: 14,
    borderWidth: 1,
    borderColor: '#E2E8F0',
    gap: 6,
  },
  recentMood: { color: '#4F46E5', fontWeight: '700' },
  recentDate: { color: '#94A3B8', fontSize: 12 },
  recentText: { color: '#0F172A', lineHeight: 20 },
  empty: { color: '#94A3B8' },
  moodRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    backgroundColor: '#F8FAFC',
    borderRadius: 12,
    paddingVertical: 10,
    paddingHorizontal: 12,
  },
  moodLabel: { color: '#0F172A', fontWeight: '600' },
  moodCount: { color: '#4F46E5', fontWeight: '700' },
});
