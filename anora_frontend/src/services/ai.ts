// Lightweight on-device AI mock. Replace with real TFLite inference later.
// Provides sentiment-ish and risk-ish signals using heuristics to unblock UI flows.

export type InferenceResult = {
  mood: 'joy' | 'calm' | 'neutral' | 'sad' | 'anxious';
  riskFlags: Array<'self-harm' | 'anxiety' | 'depression' | 'mania'>;
  themes: string[];
  score: number; // 0-1
};

const keywords = {
  sad: ['sad', 'down', 'lonely', 'tired', 'upset', 'gloom'],
  anxious: ['anxious', 'nervous', 'worry', 'panic', 'fear'],
  joy: ['happy', 'grateful', 'excited', 'good', 'proud', 'calm'],
  selfHarm: ['hurt myself', 'end it', 'suicide', 'kill myself'],
  mania: ['unstoppable', 'no sleep', 'racing thoughts'],
};

export function runLocalInference(text: string): InferenceResult {
  const lower = text.toLowerCase();
  let mood: InferenceResult['mood'] = 'neutral';
  let score = 0.5;
  const riskFlags: InferenceResult['riskFlags'] = [];
  const themes: string[] = [];

  if (keywords.joy.some((k) => lower.includes(k))) {
    mood = 'joy';
    score = 0.8;
  }
  if (keywords.sad.some((k) => lower.includes(k))) {
    mood = 'sad';
    score = 0.3;
    themes.push('low affect');
  }
  if (keywords.anxious.some((k) => lower.includes(k))) {
    mood = 'anxious';
    score = 0.35;
    themes.push('anxiety');
  }
  if (keywords.selfHarm.some((k) => lower.includes(k))) {
    riskFlags.push('self-harm');
    themes.push('safety');
  }
  if (keywords.mania.some((k) => lower.includes(k))) {
    riskFlags.push('mania');
    themes.push('activation');
  }

  // Quick heuristic for depression flag
  if (mood === 'sad' && lower.includes('no hope')) {
    riskFlags.push('depression');
  }

  return { mood, riskFlags, themes: [...new Set(themes)], score };
}
