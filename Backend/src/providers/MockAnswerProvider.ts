import type { Logger } from '../logger.js';
import { capWords, countWords } from '../text.js';
import type {
  AnswerProvider,
  AnswerProviderInput,
  AnswerProviderResult,
} from './AnswerProvider.js';

/**
 * Deterministic mock provider. Same input always yields the same answer, with
 * no network. Used until OPENROUTER_API_KEY is supplied and for tests.
 *
 * The answer is derived only from the question via a stable FNV-1a hash so the
 * output is reproducible and word-length-controlled, but does not echo the
 * question verbatim (avoids leaking the question through the answer channel in
 * predictable ways while remaining testable).
 */

const WORD_BANK = [
  'clarity', 'ink', 'quiet', 'page', 'consider', 'answer', 'thought',
  'careful', 'balance', 'signal', 'reflect', 'concise', 'measured',
  'response', 'reason', 'insight', 'reads', 'flows', 'settles', 'holds',
];

function fnv1a(input: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    h ^= input.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

export class MockAnswerProvider implements AnswerProvider {
  public readonly kind = 'mock' as const;

  public async generate(
    input: AnswerProviderInput,
    _logger: Logger,
  ): Promise<AnswerProviderResult> {
    if (input.signal.aborted) {
      throw new Error('aborted');
    }
    const seed = fnv1a(`${input.locale}\u0000${input.question}`);
    // Target roughly half the allowance, at least one word, capped by maxWords.
    const target = Math.max(1, Math.min(input.maxWords, 8 + (seed % 24)));
    const words: string[] = [];
    let state = seed || 1;
    for (let i = 0; i < target; i++) {
      state = Math.imul(state ^ (state >>> 15), 0x2c1b3c6d) >>> 0;
      const idx = state % WORD_BANK.length;
      words.push(WORD_BANK[idx] as string);
    }
    // Sentence-case the deterministic phrase.
    const raw = words.join(' ');
    const sentence = raw.charAt(0).toUpperCase() + raw.slice(1) + '.';
    const answer = capWords(sentence, input.maxWords);
    return { answer, words: countWords(answer) };
  }
}
