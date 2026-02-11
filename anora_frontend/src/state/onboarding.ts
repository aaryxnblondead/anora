import { getJSON, saveJSON, saveSecureItem, STORAGE_KEYS } from '../services/storage';

export type MoodBaseline = 'joy' | 'calm' | 'neutral' | 'sad' | 'anxious';

export async function getOnboardingStatus() {
  const complete = await getJSON<boolean>(STORAGE_KEYS.onboardingComplete);
  const name = await getJSON<string>(STORAGE_KEYS.userName);
  const mood = await getJSON<MoodBaseline>(STORAGE_KEYS.moodBaseline);
  return { complete: !!complete, name: name ?? null, mood: mood ?? null };
}

export async function saveName(name: string) {
  await saveJSON(STORAGE_KEYS.userName, name);
}

export async function saveMoodBaseline(mood: MoodBaseline) {
  await saveJSON(STORAGE_KEYS.moodBaseline, mood);
}

export async function markOnboardingComplete() {
  await Promise.all([
    saveJSON(STORAGE_KEYS.onboardingComplete, true),
    saveSecureItem('ONBOARDING_COMPLETED_AT', new Date().toISOString()),
  ]);
}
