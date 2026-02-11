import * as SecureStore from 'expo-secure-store';

// Keys used across the app for persisted state
export const STORAGE_KEYS = {
  onboardingComplete: 'ONBOARDING_COMPLETE',
  userName: 'USER_NAME',
  moodBaseline: 'MOOD_BASELINE',
  journalEntries: 'JOURNAL_ENTRIES',
  streak: 'STREAK',
  lastEntryDate: 'LAST_ENTRY_DATE',
  reminders: 'REMINDERS',
  clinicianPublicKey: 'CLINICIAN_PUBLIC_KEY',
  modelVersion: 'MODEL_VERSION',
} as const;

export async function saveSecureItem(key: string, value: string) {
  await SecureStore.setItemAsync(key, value, {
    keychainAccessible: SecureStore.AFTER_FIRST_UNLOCK,
  });
}

export async function getSecureItem(key: string): Promise<string | null> {
  return SecureStore.getItemAsync(key);
}

export async function deleteSecureItem(key: string) {
  await SecureStore.deleteItemAsync(key);
}

export async function saveJSON<T>(key: string, value: T) {
  return saveSecureItem(key, JSON.stringify(value));
}

export async function getJSON<T>(key: string): Promise<T | null> {
  const raw = await getSecureItem(key);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as T;
  } catch (err) {
    console.warn('Failed to parse stored JSON for', key, err);
    return null;
  }
}

export async function clearOnboardingState() {
  await Promise.all([
    deleteSecureItem(STORAGE_KEYS.onboardingComplete),
    deleteSecureItem(STORAGE_KEYS.userName),
    deleteSecureItem(STORAGE_KEYS.moodBaseline),
    deleteSecureItem(STORAGE_KEYS.streak),
    deleteSecureItem(STORAGE_KEYS.lastEntryDate),
    deleteSecureItem(STORAGE_KEYS.reminders),
  ]);
}

// Example: await saveSecureItem(STORAGE_KEYS.userName, 'Alex');
