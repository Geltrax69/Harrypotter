import assert from 'node:assert/strict';
import { test } from 'node:test';

import { buildApp } from '../src/app.js';
import type { AnswerProvider } from '../src/providers/AnswerProvider.js';
import { TEST_TOKEN, testConfig, uuid } from './helpers.js';

const mockProvider: AnswerProvider = {
  kind: 'mock',
  async generate(input) {
    return { answer: `Answer to ${input.question.length} chars.`, words: 4 };
  },
};

function authHeader() {
  return { authorization: `Bearer ${TEST_TOKEN}` };
}

function goodBody(n = 1) {
  return { requestId: uuid(n), question: 'What is a page?', locale: 'en', maxWords: 40 };
}

test('health endpoint requires no auth and reports provider', async () => {
  const { app } = await buildApp({ config: testConfig(), provider: mockProvider });
  const res = await app.inject({ method: 'GET', url: '/health' });
  assert.equal(res.statusCode, 200);
  const body = res.json();
  assert.equal(body.status, 'ok');
  assert.equal(body.provider, 'mock');
  await app.close();
});

test('POST /v1/answers: rejects missing auth', async () => {
  const { app } = await buildApp({ config: testConfig(), provider: mockProvider });
  const res = await app.inject({ method: 'POST', url: '/v1/answers', payload: goodBody() });
  assert.equal(res.statusCode, 401);
  assert.equal(res.json().error.code, 'unauthorized');
  await app.close();
});

test('POST /v1/answers: rejects wrong token', async () => {
  const { app } = await buildApp({ config: testConfig(), provider: mockProvider });
  const res = await app.inject({ method: 'POST', url: '/v1/answers', headers: { authorization: 'Bearer wrong-token-value-1234' }, payload: goodBody() });
  assert.equal(res.statusCode, 401);
  await app.close();
});

test('POST /v1/answers: happy path returns capped answer', async () => {
  const { app } = await buildApp({ config: testConfig(), provider: mockProvider });
  const res = await app.inject({ method: 'POST', url: '/v1/answers', headers: authHeader(), payload: goodBody() });
  assert.equal(res.statusCode, 200);
  const body = res.json();
  assert.equal(body.requestId, uuid(1));
  assert.equal(body.provider, 'mock');
  assert.equal(typeof body.answer, 'string');
  await app.close();
});

test('POST /v1/answers: validation errors are 400 with code', async () => {
  const { app } = await buildApp({ config: testConfig(), provider: mockProvider });
  const res = await app.inject({ method: 'POST', url: '/v1/answers', headers: authHeader(), payload: { requestId: 'nope', question: '', locale: 'fr', maxWords: 999 } });
  assert.equal(res.statusCode, 400);
  assert.equal(res.json().error.code, 'validation_error');
  await app.close();
});

test('POST /v1/answers: idempotent replay returns identical stored result', async () => {
  let calls = 0;
  const counting: AnswerProvider = {
    kind: 'mock',
    async generate() {
      calls++;
      return { answer: `call ${calls}`, words: 2 };
    },
  };
  const { app } = await buildApp({ config: testConfig(), provider: counting });
  const first = await app.inject({ method: 'POST', url: '/v1/answers', headers: authHeader(), payload: goodBody(7) });
  const second = await app.inject({ method: 'POST', url: '/v1/answers', headers: authHeader(), payload: goodBody(7) });
  assert.equal(first.statusCode, 200);
  assert.equal(second.statusCode, 200);
  assert.deepEqual(first.json(), second.json());
  assert.equal(calls, 1, 'provider called only once for duplicate requestId');
  await app.close();
});

test('POST /v1/answers: failed provider releases idempotency for retry', async () => {
  let calls = 0;
  const flaky: AnswerProvider = {
    kind: 'mock',
    async generate() {
      calls++;
      if (calls === 1) throw new Error('transient');
      return { answer: 'ok now', words: 2 };
    },
  };
  const { app } = await buildApp({ config: testConfig(), provider: flaky });
  const first = await app.inject({ method: 'POST', url: '/v1/answers', headers: authHeader(), payload: goodBody(8) });
  assert.equal(first.statusCode, 502);
  const second = await app.inject({ method: 'POST', url: '/v1/answers', headers: authHeader(), payload: goodBody(8) });
  assert.equal(second.statusCode, 200);
  await app.close();
});

test('body limit: oversize payload rejected as 413', async () => {
  const { app } = await buildApp({ config: testConfig({ BODY_LIMIT_BYTES: '256' }), provider: mockProvider });
  const big = { requestId: uuid(9), question: 'a'.repeat(2000), locale: 'en', maxWords: 40 };
  const res = await app.inject({ method: 'POST', url: '/v1/answers', headers: authHeader(), payload: big });
  assert.equal(res.statusCode, 413);
  await app.close();
});

test('rate limit: exceeding max returns 429', async () => {
  const { app } = await buildApp({ config: testConfig({ RATE_LIMIT_MAX: '2', RATE_LIMIT_WINDOW_MS: '60000' }), provider: mockProvider });
  const h = authHeader();
  const r1 = await app.inject({ method: 'POST', url: '/v1/answers', headers: h, payload: goodBody(20) });
  const r2 = await app.inject({ method: 'POST', url: '/v1/answers', headers: h, payload: goodBody(21) });
  const r3 = await app.inject({ method: 'POST', url: '/v1/answers', headers: h, payload: goodBody(22) });
  assert.equal(r1.statusCode, 200);
  assert.equal(r2.statusCode, 200);
  assert.equal(r3.statusCode, 429);
  assert.equal(r3.json().error.code, 'rate_limited');
  await app.close();
});

test('security headers are present (helmet)', async () => {
  const { app } = await buildApp({ config: testConfig(), provider: mockProvider });
  const res = await app.inject({ method: 'GET', url: '/health' });
  assert.ok(res.headers['x-content-type-options']);
  await app.close();
});


test('POST /v1/answers: normal request stream completion does not abort provider', async () => {
  let observedAbort = true;
  const delayed: AnswerProvider = {
    kind: 'mock',
    async generate(input) {
      await new Promise((resolve) => setTimeout(resolve, 15));
      observedAbort = input.signal.aborted;
      return { answer: 'Still connected.', words: 2 };
    },
  };
  const { app } = await buildApp({ config: testConfig(), provider: delayed });
  const res = await app.inject({
    method: 'POST',
    url: '/v1/answers',
    headers: authHeader(),
    payload: goodBody(31),
  });
  assert.equal(res.statusCode, 200);
  assert.equal(observedAbort, false);
  await app.close();
});