// A port of Sources/CoachCore/Fluency.swift.
export type Outcome = 'hit' | 'miss';
export type Stage = 'learning' | 'practicing' | 'fluent' | 'learned';

/** How long the miss flash holds, in seconds, or null for no flash. */
export const HOLD: Record<Stage, number | null> = { learning: 1.6, practicing: 1.0, fluent: 0.6, learned: null };

const WINDOW = 20;

/** Checked in order, first match wins. Below every row is `learning`. */
const STAGES: [stage: Stage, attempts: number, hitRate: number][] = [
  ['learned', WINDOW, 0.95],
  ['fluent', 10, 0.8],
  ['practicing', 5, 0.5],
];

/** From one app's hit and miss records, oldest first. */
export function fluency(records: Outcome[]): Stage {
  const attempts = records.slice(-WINDOW);
  const rate = attempts.length ? attempts.filter((o) => o === 'hit').length / attempts.length : 0;
  return STAGES.find(([, n, r]) => attempts.length >= n && rate >= r)?.[0] ?? 'learning';
}
