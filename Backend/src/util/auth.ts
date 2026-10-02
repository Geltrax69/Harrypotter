import { timingSafeEqual } from 'node:crypto';

/** Constant-time string comparison that avoids early-exit length leaks. */
export function safeEqual(a: string, b: string): boolean {
  const ab = Buffer.from(a, 'utf8');
  const bb = Buffer.from(b, 'utf8');
  if (ab.length !== bb.length) {
    // Still do a comparison to reduce timing signal, then return false.
    const pad = Buffer.alloc(ab.length);
    timingSafeEqual(ab, ab.length === pad.length ? pad : ab);
    return false;
  }
  return timingSafeEqual(ab, bb);
}

/** Extract a bearer token from an Authorization header value. */
export function extractBearer(headerValue: string | undefined): string | undefined {
  if (!headerValue) return undefined;
  const match = /^Bearer\s+(.+)$/i.exec(headerValue.trim());
  if (!match) return undefined;
  const token = match[1]?.trim();
  return token && token.length > 0 ? token : undefined;
}
