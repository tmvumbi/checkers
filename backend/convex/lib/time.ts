/** Epoch ms → ISO-8601 string (or null), the shape Postgres timestamptz
 * columns had on the wire. */
export function iso(ms: number | undefined | null): string | null {
  return ms === undefined || ms === null ? null : new Date(ms).toISOString();
}

/** UTC calendar day "YYYY-MM-DD" (Postgres `current_date` on a UTC host). */
export function utcDay(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

export const SECOND = 1000;
export const MINUTE = 60 * SECOND;
export const HOUR = 60 * MINUTE;
export const DAY = 24 * HOUR;
