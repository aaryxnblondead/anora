import React, { useEffect, useMemo, useState } from 'react';
import { View, Text, StyleSheet, TextInput, TouchableOpacity, ScrollView } from 'react-native';
import { useRouter } from 'expo-router';
import ScreenWrapper from '../../../components/ScreenWrapper';
import { getOnboardingStatus } from '../../../state/onboarding';
import { addEntry, getEntries, JournalEntry, clearEntries } from '../../../state/journal';
import { clearOnboardingState } from '../../../services/storage';
import { PROMPTS, updateStreak, getStreak, getReminders, saveReminders } from '../../../state/engagement';
import { runLocalInference } from '../../../services/ai';

const moodOptions = [
  { id: 'joy', label: 'Upbeat', emoji: '😊' },
  { id: 'calm', label: 'Calm', emoji: '😌' },
  { id: 'neutral', label: 'Neutral', emoji: '😐' },
  { id: 'sad', label: 'Low', emoji: '😢' },
  { id: 'anxious', label: 'Tense', emoji: '😰' },
];

export default function JournalScreen() {
  const [name, setName] = useState<string | null>(null);
  const [baselineMood, setBaselineMood] = useState<string | null>(null);
  const [entries, setEntries] = useState<JournalEntry[]>([]);
  const [entryText, setEntryText] = useState('');
  const [mood, setMood] = useState(moodOptions[2].id);
  const [saving, setSaving] = useState(false);
  const [streak, setStreak] = useState(0);
  const [reminders, setReminders] = useState<{ enabled: boolean; hour: number; minute: number }>({ enabled: false, hour: 20, minute: 0 });
  const router = useRouter();

  useEffect(() => {
    const load = async () => {
      const status = await getOnboardingStatus();
      setName(status.name);
      setBaselineMood(status.mood);
      const storedEntries = await getEntries();
      setEntries(storedEntries);
      const streakState = await getStreak();
      setStreak(streakState.count);
      const r = await getReminders();
      setReminders(r);
    };
    load();
  }, []);

  const handleAdd = async () => {
    const text = entryText.trim();
    if (!text) return;
    setSaving(true);
    const updated = await addEntry({ text, mood: mood as any });
    setEntries(updated);
    setEntryText('');
    const streakState = await updateStreak(new Date().toISOString());
    setStreak(streakState.count);
    setSaving(false);
  };

  const handlePromptInsert = (prompt: string) => {
    setEntryText((prev) => (prev ? `${prev}\n\n${prompt}` : prompt));
  };

  const inference = useMemo(() => (entryText.trim() ? runLocalInference(entryText) : null), [entryText]);

  const toggleReminders = async () => {
    const next = { ...reminders, enabled: !reminders.enabled };
    setReminders(next);
    await saveReminders(next);
  };

  const handleReset = async () => {
    await clearEntries();
    await clearOnboardingState();
    router.replace('/(auth)/welcome');
  };

  return (
    <ScreenWrapper>
      <ScrollView contentContainerStyle={{ paddingBottom: 32 }}>
        <View style={styles.header}>
          <Text style={styles.title}>Journal</Text>
          <Text style={styles.subtitle}>
            {name ? `Hey ${name}, this is your private space.` : 'This is your private space.'}
          </Text>
          {baselineMood && <Text style={styles.mood}>Baseline mood: {baselineMood}</Text>}
        </View>

        <View style={styles.card}>
          <Text style={styles.label}>New entry</Text>
          <View style={styles.streakRow}>
            <Text style={styles.streakLabel}>Streak</Text>
            <Text style={styles.streakValue}>{streak} day{streak === 1 ? '' : 's'}</Text>
          </View>
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.promptRow}>
            {PROMPTS.map((p) => (
              <TouchableOpacity key={p} style={styles.promptPill} onPress={() => handlePromptInsert(p)}>
                <Text style={styles.promptText}>{p}</Text>
              </TouchableOpacity>
            ))}
          </ScrollView>
          <TextInput
            style={styles.input}
            placeholder="How are you feeling right now?"
            value={entryText}
            onChangeText={setEntryText}
            multiline
            textAlignVertical="top"
          />
          {inference && (
            <View style={styles.inferenceBox}>
              <Text style={styles.inferenceTitle}>On-device AI quick read</Text>
              <Text style={styles.inferenceLine}>Mood guess: {inference.mood}</Text>
              <Text style={styles.inferenceLine}>Risk flags: {inference.riskFlags.join(', ') || 'none detected'}</Text>
              {inference.themes.length > 0 && <Text style={styles.inferenceLine}>Themes: {inference.themes.join(', ')}</Text>}
            </View>
          )}
          <View style={styles.moodRow}>
            {moodOptions.map((option) => (
              <TouchableOpacity
                key={option.id}
                style={[styles.moodPill, mood === option.id && styles.moodPillActive]}
                onPress={() => setMood(option.id)}
              >
                <Text style={styles.moodEmoji}>{option.emoji}</Text>
                <Text style={styles.moodText}>{option.label}</Text>
              </TouchableOpacity>
            ))}
          </View>
          <TouchableOpacity
            style={[styles.button, (!entryText.trim() || saving) && styles.buttonDisabled]}
            onPress={handleAdd}
            disabled={!entryText.trim() || saving}
            activeOpacity={0.85}
          >
            <Text style={styles.buttonText}>{saving ? 'Saving...' : 'Save entry'}</Text>
          </TouchableOpacity>
        </View>

        {entries.length === 0 ? (
          <View style={styles.empty}>
            <Text style={styles.emptyTitle}>No entries yet</Text>
            <Text style={styles.emptyCopy}>Start writing to capture how you feel today.</Text>
          </View>
        ) : (
          <View style={{ gap: 12 }}>
            {entries.map((entry) => (
              <View key={entry.id} style={styles.entryCard}>
                <Text style={styles.entryMood}>{entry.mood}</Text>
                <Text style={styles.entryDate}>{new Date(entry.createdAt).toLocaleString()}</Text>
                <Text style={styles.entryText}>{entry.text}</Text>
              </View>
            ))}
          </View>
        )}

        <View style={styles.reminderRow}>
          <Text style={styles.reminderLabel}>Daily reminder</Text>
          <TouchableOpacity onPress={toggleReminders} style={[styles.reminderToggle, reminders.enabled && styles.reminderToggleOn]}>
            <Text style={styles.reminderToggleText}>{reminders.enabled ? 'On' : 'Off'}</Text>
          </TouchableOpacity>
          <Text style={styles.reminderTime}>{String(reminders.hour).padStart(2, '0')}:00</Text>
        </View>

        <TouchableOpacity style={styles.resetButton} onPress={handleReset} activeOpacity={0.8}>
          <Text style={styles.resetText}>Reset onboarding (debug)</Text>
        </TouchableOpacity>
      </ScrollView>
    </ScreenWrapper>
  );
}

const styles = StyleSheet.create({
  header: { gap: 4, marginBottom: 16 },
  title: { fontSize: 28, fontWeight: '700', color: '#0F172A' },
  subtitle: { color: '#475569' },
  mood: { color: '#6366F1', fontWeight: '600' },
  card: {
    backgroundColor: '#fff',
    borderRadius: 16,
    padding: 16,
    borderWidth: 1,
    borderColor: '#E2E8F0',
    gap: 12,
    marginBottom: 20,
  },
  label: { color: '#6366F1', fontWeight: '600' },
  streakRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  streakLabel: { color: '#475569', fontWeight: '600' },
  streakValue: { color: '#0F172A', fontWeight: '700' },
  promptRow: { gap: 8, paddingVertical: 4 },
  promptPill: {
    backgroundColor: '#EEF2FF',
    borderRadius: 14,
    paddingVertical: 8,
    paddingHorizontal: 12,
    borderWidth: 1,
    borderColor: '#E0E7FF',
    marginRight: 8,
  },
  promptText: { color: '#3730A3', fontWeight: '600', maxWidth: 240 },
  input: {
    borderWidth: 1,
    borderColor: '#E2E8F0',
    borderRadius: 12,
    padding: 12,
    minHeight: 90,
    fontSize: 16,
  },
  inferenceBox: {
    borderWidth: 1,
    borderColor: '#C7D2FE',
    backgroundColor: '#EEF2FF',
    borderRadius: 12,
    padding: 10,
    gap: 4,
  },
  inferenceTitle: { color: '#312E81', fontWeight: '700' },
  inferenceLine: { color: '#4338CA' },
  moodRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  moodPill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    borderWidth: 1,
    borderColor: '#E2E8F0',
    borderRadius: 20,
    paddingVertical: 8,
    paddingHorizontal: 12,
  },
  moodPillActive: {
    borderColor: '#4F46E5',
    backgroundColor: '#EEF2FF',
  },
  moodEmoji: { fontSize: 18 },
  moodText: { color: '#0F172A', fontWeight: '600' },
  button: {
    backgroundColor: '#4F46E5',
    borderRadius: 12,
    paddingVertical: 14,
    alignItems: 'center',
  },
  buttonDisabled: { opacity: 0.6 },
  buttonText: { color: '#fff', fontWeight: '700', fontSize: 16 },
  empty: {
    borderWidth: 1,
    borderColor: '#E2E8F0',
    borderStyle: 'dashed',
    borderRadius: 16,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 24,
  },
  emptyTitle: { fontSize: 18, fontWeight: '700', color: '#0F172A' },
  emptyCopy: { color: '#64748B', marginTop: 4 },
  entryCard: {
    backgroundColor: '#FFFFFF',
    borderRadius: 14,
    padding: 14,
    borderWidth: 1,
    borderColor: '#E2E8F0',
    gap: 6,
  },
  entryMood: { color: '#4F46E5', fontWeight: '700' },
  entryDate: { color: '#94A3B8', fontSize: 12 },
  entryText: { color: '#0F172A', fontSize: 15, lineHeight: 20 },
  reminderRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginTop: 16,
    borderWidth: 1,
    borderColor: '#E2E8F0',
    borderRadius: 12,
    padding: 12,
  },
  reminderLabel: { color: '#0F172A', fontWeight: '700', flex: 1 },
  reminderToggle: {
    paddingVertical: 6,
    paddingHorizontal: 10,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: '#CBD5E1',
  },
  reminderToggleOn: { backgroundColor: '#EEF2FF', borderColor: '#4F46E5' },
  reminderToggleText: { color: '#1E293B', fontWeight: '600' },
  reminderTime: { color: '#475569', fontWeight: '600' },
  resetButton: {
    marginTop: 16,
    alignSelf: 'center',
    padding: 12,
  },
  resetText: { color: '#EF4444', fontWeight: '600' },
});
