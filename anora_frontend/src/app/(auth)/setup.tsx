import React, { useState } from 'react';
import { View, Text, TextInput, StyleSheet } from 'react-native';
import ScreenWrapper from '../../components/ScreenWrapper';
import Button from '../../components/ui/Button';
import { useRouter } from 'expo-router';
import { saveName } from '../../state/onboarding';

export default function SetupScreen() {
  const [name, setName] = useState('');
  const [saving, setSaving] = useState(false);
  const router = useRouter();

  const handleNext = async () => {
    if (!name.trim()) return;
    setSaving(true);
    await saveName(name.trim());
    router.push('/(auth)/mood-baseline');
  };

  return (
    <ScreenWrapper style={styles.container}>
      <View style={styles.progress}>
        <View style={[styles.progressBar, { width: '66%' }]} />
      </View>
      <View style={styles.card}>
        <Text style={styles.label}>Introduce yourself</Text>
        <Text style={styles.title}>What should we call you?</Text>
        <Text style={styles.subtitle}>We keep this on device to personalize your journal.</Text>
        <TextInput
          style={styles.input}
          placeholder="Name or nickname"
          value={name}
          onChangeText={setName}
          autoCapitalize="words"
          returnKeyType="next"
        />
        <Button title={saving ? 'Saving...' : 'Next'} onPress={handleNext} disabled={!name.trim() || saving} />
      </View>
    </ScreenWrapper>
  );
}

const styles = StyleSheet.create({
  container: { paddingTop: 40, gap: 16 },
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
  card: {
    backgroundColor: '#FFFFFF',
    borderRadius: 20,
    padding: 20,
    gap: 12,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.06,
    shadowRadius: 10,
    elevation: 3,
  },
  label: { color: '#6366F1', fontWeight: '600', fontSize: 14 },
  title: { fontSize: 24, fontWeight: '700', color: '#0F172A' },
  subtitle: { color: '#475569', lineHeight: 20 },
  input: {
    borderWidth: 1,
    borderColor: '#E2E8F0',
    borderRadius: 12,
    padding: 14,
    fontSize: 16,
    marginTop: 4,
  },
});
