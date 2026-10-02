/**
 * Plain-text normalization and word capping shared by providers.
 */

/** Collapse whitespace and strip control chars to a single-line-safe string. */
export function normalizePlainText(input: string): string {
  return input
    // Drop C0/C1 control chars except newline/tab which we convert to space.
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, '')
    .replace(/[\r\n\t]+/g, ' ')
    .replace(/[ \u00A0\u2000-\u200A\u202F\u205F\u3000]+/g, ' ')
    .trim();
}

/** Split into words on Unicode whitespace. */
export function countWords(input: string): number {
  const t = input.trim();
  if (t.length === 0) return 0;
  return t.split(/\s+/u).length;
}

/**
 * Cap a normalized string to at most `maxWords` words. If truncated, appends a
 * single ellipsis character to the last kept word boundary.
 */
export function capWords(input: string, maxWords: number): string {
  const normalized = normalizePlainText(input);
  if (normalized.length === 0) return '';
  const words = normalized.split(/\s+/u);
  if (words.length <= maxWords) return normalized;
  const kept = words.slice(0, maxWords).join(' ');
  return `${kept}\u2026`;
}
