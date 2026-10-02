/**
 * Bounded, in-memory idempotency store keyed by request id.
 *
 * - LRU-ish eviction: when at capacity, the oldest inserted entry is dropped.
 * - TTL expiry on read and on periodic sweep.
 * - Stores three states: `pending` (in-flight), `done` (result), so concurrent
 *   duplicate requests can be detected.
 *
 * This is intentionally process-local; a multi-instance deployment would swap
 * this for a shared store, but the interface stays the same.
 */

export type IdempotencyEntry<T> =
  | { state: 'pending'; createdAt: number }
  | { state: 'done'; createdAt: number; value: T };

export class IdempotencyStore<T> {
  private readonly map = new Map<string, IdempotencyEntry<T>>();

  public constructor(
    private readonly maxEntries: number,
    private readonly ttlMs: number,
    private readonly now: () => number = Date.now,
  ) {}

  private isExpired(entry: IdempotencyEntry<T>): boolean {
    return this.now() - entry.createdAt > this.ttlMs;
  }

  public get(key: string): IdempotencyEntry<T> | undefined {
    const entry = this.map.get(key);
    if (!entry) return undefined;
    if (this.isExpired(entry)) {
      this.map.delete(key);
      return undefined;
    }
    return entry;
  }

  /** Reserve a key as pending. Returns false if a live entry already exists. */
  public reservePending(key: string): boolean {
    const existing = this.get(key);
    if (existing) return false;
    this.evictIfNeeded();
    this.map.set(key, { state: 'pending', createdAt: this.now() });
    return true;
  }

  public complete(key: string, value: T): void {
    this.map.set(key, { state: 'done', createdAt: this.now(), value });
  }

  /** Remove a pending reservation (e.g. on failure) so retries can proceed. */
  public release(key: string): void {
    const entry = this.map.get(key);
    if (entry && entry.state === 'pending') {
      this.map.delete(key);
    }
  }

  private evictIfNeeded(): void {
    if (this.map.size < this.maxEntries) return;
    // Delete oldest-inserted entries until under capacity.
    const overflow = this.map.size - this.maxEntries + 1;
    let removed = 0;
    for (const key of this.map.keys()) {
      this.map.delete(key);
      if (++removed >= overflow) break;
    }
  }

  public sweep(): void {
    for (const [key, entry] of this.map) {
      if (this.isExpired(entry)) this.map.delete(key);
    }
  }

  public get size(): number {
    return this.map.size;
  }
}
