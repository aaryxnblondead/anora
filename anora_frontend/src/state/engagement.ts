import { getJSON, saveJSON, STORAGE_KEYS } from '../services/storage';

export type ReminderSettings = {
  enabled: boolean;
  hour: number; // 0-23
  minute: number; // 0-59
};

export async function getStreak() {
  const stored = await getJSON<{ count: number; lastDate: string }>(STORAGE_KEYS.streak);
  return stored ?? { count: 0, lastDate: '' };
}

export async function updateStreak(todayISO: string) {
  const current = await getStreak();
  const today = todayISO.slice(0, 10);
  const last = current.lastDate.slice(0, 10);
  let count = current.count;

  if (last === today) {
    return current;
  }
  if (last) {
    const lastDate = new Date(last);
    const nextDate = new Date(lastDate);
    nextDate.setDate(lastDate.getDate() + 1);
    const nextISO = nextDate.toISOString().slice(0, 10);
    count = nextISO === today ? count + 1 : 1;
  } else {
    count = 1;
  }

  const updated = { count, lastDate: todayISO };
  await saveJSON(STORAGE_KEYS.streak, updated);
  await saveJSON(STORAGE_KEYS.lastEntryDate, todayISO);
  return updated;
}

export const PROMPTS = [
  'What gave you a moment of calm today?',
  'What felt heavy, and why?',
  'Who or what made you feel supported?',
  'Describe a worry. What would you tell a friend about it?',
  'Name one small win you had today.',
];

export async function getReminders(): Promise<ReminderSettings> {
  const stored = await getJSON<ReminderSettings>(STORAGE_KEYS.reminders);
  return stored ?? { enabled: false, hour: 20, minute: 0 };
}

export async function saveReminders(settings: ReminderSettings) {
  await saveJSON(STORAGE_KEYS.reminders, settings);
}
