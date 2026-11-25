// UTC days and streaks. Pure functions, no I/O.
//
// A day is a UTC calendar day. The contract numbers them `block.timestamp / 86400`; this server
// writes the same day as YYYY-MM-DD in its API and in the text a member signs.

export const DAY_SECONDS = 86_400;

/** The contract's day number for a unix time in seconds. */
export const dayIndexAt = (unix: number): number => Math.floor(unix / DAY_SECONDS);

/** YYYY-MM-DD of a day number. */
export const dayString = (index: number): string => new Date(index * DAY_SECONDS * 1000).toISOString().slice(0, 10);

/** Day number of a YYYY-MM-DD string, or null if it is not a real date. */
export function dayIndexOf(day: string): number | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) return null;
  const ms = Date.parse(`${day}T00:00:00Z`);
  if (Number.isNaN(ms) || new Date(ms).toISOString().slice(0, 10) !== day) return null;
  return ms / 1000 / DAY_SECONDS;
}

export interface Streaks {
  /** Consecutive days ending today, or ending yesterday when today has no check-in yet. */
  streak: number;
  /** The longest run of consecutive days so far. */
  bestStreak: number;
}

/**
 * Streaks from a list of checked-in days (YYYY-MM-DD, any order, duplicates ignored).
 *
 * The current streak still counts when it ends yesterday: the member has until the end of today
 * (UTC) to keep it going. A gap of one full day ends it.
 */
export function streaks(days: string[], today: number): Streaks {
  const set = new Set<number>();
  for (const d of days) {
    const index = dayIndexOf(d);
    if (index !== null) set.add(index);
  }
  let bestStreak = 0;
  for (const d of set) {
    if (set.has(d - 1)) continue; // not the first day of a run
    let length = 1;
    while (set.has(d + length)) length++;
    bestStreak = Math.max(bestStreak, length);
  }
  let end = set.has(today) ? today : set.has(today - 1) ? today - 1 : null;
  let streak = 0;
  while (end !== null && set.has(end)) {
    streak++;
    end--;
  }
  return { streak, bestStreak };
}
