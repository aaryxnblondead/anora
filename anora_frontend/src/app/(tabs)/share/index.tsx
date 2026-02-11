import React, { useEffect, useState } from 'react';
import { View, Text, StyleSheet, TextInput, TouchableOpacity, ScrollView } from 'react-native';
import ScreenWrapper from '../../../components/ScreenWrapper';
import { getEntries } from '../../../state/journal';
import { buildLockedBox, getClinicianPublicKey, saveClinicianPublicKey } from '../../../features/share/summary';

export default function ShareScreen() {
  const [entriesCount, setEntriesCount] = useState(0);
  const [publicKey, setPublicKey] = useState('');
  const [lockedBox, setLockedBox] = useState<{ encryptedPayload: string; encryptedKey: string } | null>(null);
  const [status, setStatus] = useState('');

  useEffect(() => {
    const load = async () => {
      const storedKey = await getClinicianPublicKey();
      if (storedKey) setPublicKey(storedKey);
      const entries = await getEntries();
      setEntriesCount(entries.length);
    };
    load();
  }, []);

  const handleGenerate = async () => {
    setStatus('Generating locked box...');
    const entries = await getEntries();
    const key = publicKey.trim();
    if (!key) {
      setStatus('Clinician public key is required.');
      return;
    }
    await saveClinicianPublicKey(key);
    const box = await buildLockedBox(entries, key);
    setLockedBox({ encryptedPayload: box.encryptedPayload, encryptedKey: box.encryptedKey });
    setStatus(`Prepared ${entries.length} entries for sharing.`);
  };

  return (
    <ScreenWrapper>
      <ScrollView contentContainerStyle={{ paddingBottom: 32 }}>
        <View style={styles.header}>
          <Text style={styles.title}>Share with clinician</Text>
          <Text style={styles.subtitle}>Creates a locked box with summaries only. Raw text stays on device.</Text>
        </View>

        <View style={styles.card}>
          <Text style={styles.label}>Clinician public key</Text>
          <TextInput
            style={styles.input}
            placeholder="Paste RSA public key or test token"
            value={publicKey}
            onChangeText={setPublicKey}
            multiline
          />
          <Text style={styles.hint}>We store this locally only to speed up future shares.</Text>
        </View>

        <View style={styles.card}>
          <Text style={styles.label}>Entries ready</Text>
          <Text style={styles.value}>{entriesCount}</Text>
          <TouchableOpacity style={styles.button} onPress={handleGenerate}>
            <Text style={styles.buttonText}>Generate locked box</Text>
          </TouchableOpacity>
          {status ? <Text style={styles.status}>{status}</Text> : null}
        </View>

        {lockedBox && (
          <View style={styles.card}>
            <Text style={styles.label}>Encrypted payload</Text>
            <Text style={styles.mono}>{lockedBox.encryptedPayload}</Text>
            <Text style={styles.label}>Encrypted key</Text>
            <Text style={styles.mono}>{lockedBox.encryptedKey}</Text>
            <Text style={styles.hint}>Send both parts to the Blind Mailman server. The clinician unlocks with their private key.</Text>
          </View>
        )}
      </ScrollView>
    </ScreenWrapper>
  );
}

const styles = StyleSheet.create({
  header: { gap: 6, marginBottom: 16 },
  title: { fontSize: 28, fontWeight: '700', color: '#0F172A' },
  subtitle: { color: '#475569' },
  card: {
    backgroundColor: '#fff',
    borderRadius: 16,
    padding: 16,
    borderWidth: 1,
    borderColor: '#E2E8F0',
    gap: 8,
    marginBottom: 16,
  },
  label: { color: '#6366F1', fontWeight: '700' },
  value: { fontSize: 24, fontWeight: '700', color: '#0F172A' },
  input: {
    borderWidth: 1,
    borderColor: '#E2E8F0',
    borderRadius: 12,
    padding: 12,
    minHeight: 60,
  },
  hint: { color: '#94A3B8', fontSize: 12 },
  button: {
    backgroundColor: '#4F46E5',
    paddingVertical: 12,
    borderRadius: 12,
    alignItems: 'center',
  },
  buttonText: { color: '#fff', fontWeight: '700' },
  status: { color: '#0F172A' },
  mono: {
    fontFamily: 'monospace',
    color: '#0F172A',
    backgroundColor: '#F8FAFC',
    padding: 8,
    borderRadius: 8,
  },
});
