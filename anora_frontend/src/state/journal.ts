import { STORAGE_KEYS, getJSON, saveJSON, deleteSecureItem } from '../services/storage';
import { MoodBaseline } from './onboarding';

export type JournalEntry = {
  id: string;
  text: string;
  mood: MoodBaseline;
  createdAt: string; // ISO string
};

export async function getEntries(): Promise<JournalEntry[]> {
  const stored = await getJSON<JournalEntry[]>(STORAGE_KEYS.journalEntries);
  if (!stored) return [];
  return stored.sort((a, b) => (a.createdAt < b.createdAt ? 1 : -1));
}

export async function addEntry(input: { text: string; mood: MoodBaseline }): Promise<JournalEntry[]> {
  const current = await getEntries();
  const entry: JournalEntry = {
    id: `${Date.now()}-${Math.round(Math.random() * 1e5)}`,
    text: input.text,
    mood: input.mood,
    createdAt: new Date().toISOString(),
  };
  const updated = [entry, ...current];
  await saveJSON(STORAGE_KEYS.journalEntries, updated);
  return updated;
}

export async function clearEntries() {
  await deleteSecureItem(STORAGE_KEYS.journalEntries);
}
