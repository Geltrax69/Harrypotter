import assert from 'node:assert/strict';
import { Writable } from 'node:stream';
import { test } from 'node:test';

import { pino } from 'pino';

import { buildApp } from '../src/app.js';
import type { AnswerProvider } from '../src/providers/AnswerProvider.js';
import { TEST_TOKEN, testConfig, uuid } from './helpers.js';

const SECRET_QUESTION = 'SUPERSECRETQUESTIONTOKEN12345';
const SECRET_ANSWER = 'SUPERSECRETANSWERPHRASE67890';

function captureLogger() {
  const lines: string[] = [];
  const sink = new Writable({
    write(chunk, _enc, cb) {
      lines.push(chunk.toString());
      cb();
    },
  });
  // Build a logger with the same redaction paths as production.
  const logger = pino(
    {
      level: 'info',
      redact: { paths: ['question', 'answer', 'token', 'authorization', 'apiKey', 'openrouterApiKey', 'deviceAuthToken', 'prompt', 'req.headers.authorization', 'req.body.question'], censor: '[redacted]' },
    },
    sink,
  );
  return { logger, lines };
}

test('logs never contain question, answer, or token values', async () => {
  const { logger, lines } = captureLogger();
  const provider: AnswerProvider = {
    kind: 'mock',
    async generate() {
      return { answer: SECRET_ANSWER, words: 3 };
    },
  };
  const { app } = await buildApp({ config: testConfig(), logger, provider });

  const res = await app.inject({
    method: 'POST',
    url: '/v1/answers',
    headers: { authorization: `Bearer ${TEST_TOKEN}` },
    payload: { requestId: uuid(3), question: SECRET_QUESTION, locale: 'en', maxWords: 40 },
  });
  assert.equal(res.statusCode, 200);

  // Force any buffered logs to flush before asserting.
  await new Promise((r) => setImmediate(r));
  const all = lines.join('\n');

  assert.ok(!all.includes(SECRET_QUESTION), 'question must not appear in logs');
  assert.ok(!all.includes(SECRET_ANSWER), 'answer must not appear in logs');
  assert.ok(!all.includes(TEST_TOKEN), 'device token must not appear in logs');
  await app.close();
});

test('explicit redact censors known sensitive keys if logged directly', () => {
  const { logger, lines } = captureLogger();
  logger.info({ question: SECRET_QUESTION, answer: SECRET_ANSWER, token: TEST_TOKEN }, 'oops');
  const all = lines.join('\n');
  assert.ok(all.includes('[redacted]'));
  assert.ok(!all.includes(SECRET_QUESTION));
  assert.ok(!all.includes(SECRET_ANSWER));
  assert.ok(!all.includes(TEST_TOKEN));
});
