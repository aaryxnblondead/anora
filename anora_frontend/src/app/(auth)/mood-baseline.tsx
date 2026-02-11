import React, { useState } from 'react';
import { View, Text, StyleSheet, TouchableOpacity } from 'react-native';
import ScreenWrapper from '../../components/ScreenWrapper';
import Button from '../../components/ui/Button';
import { useRouter } from 'expo-router';
import { markOnboardingComplete, MoodBaseline, saveMoodBaseline } from '../../state/onboarding';

const moods: { id: MoodBaseline; label: string; emoji: string; copy: string }[] = [
  { id: 'joy', label: 'Upbeat', emoji: '😊', copy: 'Feeling light and optimistic' },
  { id: 'calm', label: 'Calm', emoji: '😌', copy: 'Steady and centered' },
  { id: 'neutral', label: 'Neutral', emoji: '😐', copy: 'Even and steady' },
  { id: 'sad', label: 'Low', emoji: '😢', copy: 'A bit heavy today' },
  { id: 'anxious', label: 'Tense', emoji: '😰', copy: 'Restless or worried' },
];

export default function MoodBaselineScreen() {
  const [selected, setSelected] = useState<MoodBaseline | null>(null);
  const [saving, setSaving] = useState(false);
  const router = useRouter();

  const handleFinish = async () => {
    if (!selected) return;
    setSaving(true);
    await saveMoodBaseline(selected);
    await markOnboardingComplete();
    router.replace('/(tabs)/journal');
  };

  return (
    <ScreenWrapper style={styles.container}>
      <View style={styles.progress}>
        <View style={[styles.progressBar, { width: '100%' }]} />
      </View>
      <Text style={styles.title}>How do you feel today?</Text>
      <Text style={styles.subtitle}>Pick the closest match. You can always update this later.</Text>
      <View style={styles.moodGrid}>
        {moods.map((mood) => (
          <TouchableOpacity
            key={mood.id}
            style={[styles.moodCard, selected === mood.id && styles.moodCardSelected]}
            onPress={() => setSelected(mood.id)}
            activeOpacity={0.8}
          >
            <Text style={styles.emoji}>{mood.emoji}</Text>
            <Text style={styles.moodLabel}>{mood.label}</Text>
            <Text style={styles.moodCopy}>{mood.copy}</Text>
          </TouchableOpacity>
        ))}
      </View>
      <Button title={saving ? 'Saving...' : 'Finish'} onPress={handleFinish} disabled={!selected || saving} />
    </ScreenWrapper>
  );
}

const styles = StyleSheet.create({
  container: { paddingTop: 32, gap: 16 },
  progress: {
    height: 4,
    backgroundColor: '#E2E8F0',
    borderRadius: 2,
    marginHorizontal: 4,
  },
  progressBar: {
    height: '100%',
    backgroundColor: '#4F46E5',
    borderRadius: 2,
  },
  title: { fontSize: 24, fontWeight: '700', color: '#0F172A' },
  subtitle: { color: '#475569', marginBottom: 8 },
  moodGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 12,
    justifyContent: 'space-between',
  },
  moodCard: {
    width: '48%',
    backgroundColor: '#fff',
    borderRadius: 16,
    padding: 16,
    borderWidth: 1,
    borderColor: '#E2E8F0',
    gap: 6,
  },
  moodCardSelected: {
    borderColor: '#4F46E5',
    backgroundColor: '#EEF2FF',
  },
  emoji: { fontSize: 28 },
  moodLabel: { fontWeight: '700', fontSize: 16, color: '#0F172A' },
  moodCopy: { color: '#475569', fontSize: 13 },
});
