import { JournalEntry } from '../../state/journal';
import { runLocalInference } from '../../services/ai';
import { getSecureItem, saveSecureItem, STORAGE_KEYS } from '../../services/storage';

export type ClinicianSummary = {
  entries: number;
  from: string;
  to: string;
  topMood: string | null;
  riskFlags: string[];
  highlights: Array<{ id: string; excerpt: string; mood: string; risk: string[]; at: string }>;
};

function summarize(entries: JournalEntry[]): ClinicianSummary {
  if (entries.length === 0) {
    return {
      entries: 0,
      from: '',
      to: '',
      topMood: null,
      riskFlags: [],
      highlights: [],
    };
  }

  const sorted = [...entries].sort((a, b) => (a.createdAt < b.createdAt ? -1 : 1));
  const counts: Record<string, number> = {};
  const riskSet = new Set<string>();
  const highlights: ClinicianSummary['highlights'] = [];

  sorted.forEach((entry) => {
    counts[entry.mood] = (counts[entry.mood] || 0) + 1;
    const inference = runLocalInference(entry.text);
    inference.riskFlags.forEach((r) => riskSet.add(r));
    if (inference.riskFlags.length > 0) {
      highlights.push({
        id: entry.id,
        excerpt: entry.text.slice(0, 140),
        mood: inference.mood,
        risk: inference.riskFlags,
        at: entry.createdAt,
      });
    }
  });

  const topMood = Object.entries(counts).sort((a, b) => b[1] - a[1])[0]?.[0] ?? null;

  return {
    entries: sorted.length,
    from: sorted[0].createdAt,
    to: sorted[sorted.length - 1].createdAt,
    topMood,
    riskFlags: Array.from(riskSet),
    highlights,
  };
}

// Pseudo encryption to unblock UI; replace with hybrid RSA/AES implementation tied to hardware keystore.
function pseudoEncrypt(payload: string, clinicianPublicKey: string) {
  const reversed = payload.split('').reverse().join('');
  // In production, replace with hybrid RSA/AES. Here we just obfuscate to unblock UI flows.
  return `${clinicianPublicKey}::${reversed}`;
}

export async function getClinicianPublicKey(): Promise<string | null> {
  return getSecureItem(STORAGE_KEYS.clinicianPublicKey);
}

export async function saveClinicianPublicKey(key: string) {
  await saveSecureItem(STORAGE_KEYS.clinicianPublicKey, key);
}

export async function buildLockedBox(entries: JournalEntry[], clinicianPublicKey: string) {
  const summary = summarize(entries);
  const payload = JSON.stringify(summary);
  const encryptedPayload = pseudoEncrypt(payload, clinicianPublicKey);
  const encryptedKey = `wrapped-key-for-${clinicianPublicKey}`;
  return {
    summary,
    encryptedPayload,
    encryptedKey,
  };
}
