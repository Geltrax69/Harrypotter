import assert from 'node:assert/strict';
import { test } from 'node:test';

import { loadConfig } from '../src/config.js';
import { answerRequestSchema, SUPPORTED_LOCALES } from '../src/schema.js';
import { capWords, countWords, normalizePlainText } from '../src/text.js';
import { TEST_TOKEN, uuid } from './helpers.js';

test('config: forces mock mode without OPENROUTER_API_KEY even if PROVIDER=openrouter', () => {
  const cfg = loadConfig({ DEVICE_AUTH_TOKEN: TEST_TOKEN, PROVIDER: 'openrouter' });
  assert.equal(cfg.effectiveProvider, 'mock');
  assert.equal(cfg.openrouterApiKey, undefined);
});

test('config: openrouter mode when key present; model list splits on commas', () => {
  const cfg = loadConfig({
    DEVICE_AUTH_TOKEN: TEST_TOKEN,
    PROVIDER: 'openrouter',
    OPENROUTER_API_KEY: 'k',
    OPENROUTER_MODEL: 'a:free, b:free',
  });
  assert.equal(cfg.effectiveProvider, 'openrouter');
  assert.deepEqual(cfg.openrouterModels, ['a:free', 'b:free']);
});

test('config: rejects short device token', () => {
  assert.throws(() => loadConfig({ DEVICE_AUTH_TOKEN: 'short' }));
});

test('text: normalizePlainText collapses whitespace and strips control chars', () => {
  assert.equal(normalizePlainText('a\n\tb   c\u0000d'), 'a b cd');
});

test('text: capWords caps to maxWords with ellipsis', () => {
  const capped = capWords('one two three four five', 3);
  assert.equal(capped, 'one two three\u2026');
  assert.equal(countWords('one two three'), 3);
});

test('text: capWords passes through when under limit', () => {
  assert.equal(capWords('one two', 5), 'one two');
});

test('schema: trims question and enforces nonempty', () => {
  const r = answerRequestSchema.safeParse({
    requestId: uuid(),
    question: '  hello  ',
    locale: 'en',
    maxWords: 40,
  });
  assert.ok(r.success);
  assert.equal(r.data.question, 'hello');
});

test('schema: rejects empty (whitespace-only) question', () => {
  const r = answerRequestSchema.safeParse({
    requestId: uuid(),
    question: '     ',
    locale: 'en',
    maxWords: 40,
  });
  assert.equal(r.success, false);
});

test('schema: rejects question over 2000 chars', () => {
  const r = answerRequestSchema.safeParse({
    requestId: uuid(),
    question: 'a'.repeat(2001),
    locale: 'en',
    maxWords: 40,
  });
  assert.equal(r.success, false);
});

test('schema: rejects bad locale', () => {
  const r = answerRequestSchema.safeParse({
    requestId: uuid(),
    question: 'hi',
    locale: 'fr-FR',
    maxWords: 40,
  });
  assert.equal(r.success, false);
});

test('schema: maxWords bounds 1..120', () => {
  for (const [mw, ok] of [[0, false], [1, true], [120, true], [121, false]] as const) {
    const r = answerRequestSchema.safeParse({ requestId: uuid(), question: 'hi', locale: 'en', maxWords: mw });
    assert.equal(r.success, ok, `maxWords=${mw}`);
  }
});

test('schema: rejects non-uuid requestId and unknown keys', () => {
  assert.equal(
    answerRequestSchema.safeParse({ requestId: 'nope', question: 'hi', locale: 'en', maxWords: 5 }).success,
    false,
  );
  assert.equal(
    answerRequestSchema.safeParse({ requestId: uuid(), question: 'hi', locale: 'en', maxWords: 5, extra: 1 }).success,
    false,
  );
});

test('schema: supported locales are all English/Latin', () => {
  assert.ok(SUPPORTED_LOCALES.every((l) => l.startsWith('en')));
});
