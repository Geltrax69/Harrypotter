import { z } from 'zod';

/**
 * Wire schema for POST /v1/answers. This is the ONLY data allowed across the
 * network from the device: confirmed recognized text, locale, a request id,
 * and an answer-length limit. No stroke data, no personal profile.
 */

// Constrained set of English/Latin locales for the prototype.
export const SUPPORTED_LOCALES = [
  'en',
  'en-US',
  'en-GB',
  'en-AU',
  'en-CA',
] as const;

export const MAX_QUESTION_CHARS = 2000;
export const MAX_WORDS_LIMIT = 120;
export const MIN_WORDS_LIMIT = 1;

export const answerRequestSchema = z
  .object({
    requestId: z.string().uuid('requestId must be a UUID'),
    question: z
      .string()
      .transform((s) => s.trim())
      .pipe(
        z
          .string()
          .min(1, 'question must not be empty')
          .max(MAX_QUESTION_CHARS, `question must be at most ${MAX_QUESTION_CHARS} characters`),
      ),
    locale: z.enum(SUPPORTED_LOCALES),
    maxWords: z
      .number()
      .int('maxWords must be an integer')
      .min(MIN_WORDS_LIMIT, `maxWords must be at least ${MIN_WORDS_LIMIT}`)
      .max(MAX_WORDS_LIMIT, `maxWords must be at most ${MAX_WORDS_LIMIT}`),
  })
  .strict();

export type AnswerRequest = z.infer<typeof answerRequestSchema>;

export type AnswerResponse = {
  requestId: string;
  answer: string;
  words: number;
  locale: string;
  provider: 'mock' | 'openrouter';
};
