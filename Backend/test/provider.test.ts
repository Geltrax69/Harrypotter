import assert from 'node:assert/strict';
import { test } from 'node:test';

import { createLogger } from '../src/logger.js';
import { MockAnswerProvider } from '../src/providers/MockAnswerProvider.js';
import { countWords } from '../src/text.js';
import { uuid } from './helpers.js';

const logger = createLogger('silent');

test('mock provider is deterministic for identical input', async () => {
  const p = new MockAnswerProvider();
  const input = { question: 'What is ink?', locale: 'en', maxWords: 40, requestId: uuid(), signal: new AbortController().signal };
  const a = await p.generate(input, logger);
  const b = await p.generate(input, logger);
  assert.equal(a.answer, b.answer);
  assert.equal(a.words, b.words);
});

test('mock provider differs across different questions', async () => {
  const p = new MockAnswerProvider();
  const sig = new AbortController().signal;
  const a = await p.generate({ question: 'A', locale: 'en', maxWords: 40, requestId: uuid(), signal: sig }, logger);
  const b = await p.generate({ question: 'B', locale: 'en', maxWords: 40, requestId: uuid(), signal: sig }, logger);
  assert.notEqual(a.answer, b.answer);
});

test('mock provider respects maxWords', async () => {
  const p = new MockAnswerProvider();
  const sig = new AbortController().signal;
  const r = await p.generate({ question: 'long', locale: 'en', maxWords: 3, requestId: uuid(), signal: sig }, logger);
  assert.ok(countWords(r.answer) <= 3);
});

test('mock provider throws when aborted', async () => {
  const p = new MockAnswerProvider();
  const ac = new AbortController();
  ac.abort();
  await assert.rejects(() =>
    p.generate({ question: 'x', locale: 'en', maxWords: 5, requestId: uuid(), signal: ac.signal }, logger),
  );
});
