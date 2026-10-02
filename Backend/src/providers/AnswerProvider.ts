import type { Logger } from '../logger.js';

/**
 * Adapter interface for answer providers. Providers can be
 * swapped without touching routes: all implement
 * `AnswerProvider`.
 */

export type AnswerProviderInput = {
  /** Confirmed recognized question text (already trimmed and validated). */
  question: string;
  locale: string;
  maxWords: number;
  /** Correlation id for logs only; never influences answer content. */
  requestId: string;
  /** Abort signal wired to server shutdown / request cancellation. */
  signal: AbortSignal;
};

export type AnswerProviderResult = {
  /** Normalized, word-capped plain-text answer. */
  answer: string;
  words: number;
};

export interface AnswerProvider {
  readonly kind: 'mock' | 'openrouter';
  generate(input: AnswerProviderInput, logger: Logger): Promise<AnswerProviderResult>;
}
