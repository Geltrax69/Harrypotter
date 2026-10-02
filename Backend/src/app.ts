import { createHash, randomUUID } from 'node:crypto';

import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import Fastify, {
  type FastifyBaseLogger,
  type FastifyInstance,
  type FastifyReply,
  type FastifyRequest,
} from 'fastify';

import type { AppConfig } from './config.js';
import { AppError, isAppError, UnauthorizedError, ValidationError } from './errors.js';
import { IdempotencyStore } from './idempotency.js';
import { createLogger, type Logger } from './logger.js';
import { createProvider } from './providers/factory.js';
import type { AnswerProvider } from './providers/AnswerProvider.js';
import { answerRequestSchema, type AnswerResponse } from './schema.js';
import { extractBearer, safeEqual } from './util/auth.js';

export type BuildAppOptions = {
  config: AppConfig;
  logger?: Logger;
  /** Override provider (used by tests). */
  provider?: AnswerProvider;
};

export type BuiltApp = {
  app: FastifyInstance;
  idempotency: IdempotencyStore<AnswerResponse>;
};

/** Short, non-reversible fingerprint of the token for per-token rate keying. */
function tokenFingerprint(token: string): string {
  return createHash('sha256').update(token).digest('hex').slice(0, 16);
}

export async function buildApp(opts: BuildAppOptions): Promise<BuiltApp> {
  const { config } = opts;
  const logger = opts.logger ?? createLogger(config.logLevel);

  const app = Fastify({
    logger: logger as FastifyBaseLogger,
    disableRequestLogging: true, // we log explicitly with controlled fields
    bodyLimit: config.bodyLimitBytes,
    trustProxy: config.trustProxy,
    genReqId: () => randomUUID(),
    ajv: { customOptions: { allErrors: false } },
  });

  const provider = opts.provider ?? createProvider(config);
  const idempotency = new IdempotencyStore<AnswerResponse>(
    config.idempotencyMaxEntries,
    config.idempotencyTtlMs,
  );

  await app.register(helmet, {
    // API server: no CSP report endpoints, disable cross-origin resource sharing niceties.
    contentSecurityPolicy: false,
    crossOriginEmbedderPolicy: false,
  });

  await app.register(rateLimit, {
    global: true,
    max: config.rateLimitMax,
    timeWindow: config.rateLimitWindowMs,
    // Key by device-token fingerprint when present, else client IP.
    keyGenerator: (req: FastifyRequest) => {
      const token = extractBearer(req.headers.authorization);
      if (token) return `tok:${tokenFingerprint(token)}`;
      return `ip:${req.ip}`;
    },
  });

  // Minimal controlled request logging (no bodies/headers/secrets).
  app.addHook('onResponse', (req, reply, done) => {
    logger.info(
      {
        event: 'request',
        reqId: req.id,
        method: req.method,
        route: req.routeOptions.url ?? req.url.split('?')[0],
        status: reply.statusCode,
      },
      'request completed',
    );
    done();
  });

  // Centralized typed error handling with safe payloads.
  app.setErrorHandler((err, req, reply) => {
    // Fastify body-limit error.
    if ((err as { statusCode?: number }).statusCode === 413) {
      reply.status(413).send({ error: { code: 'payload_too_large', message: 'Request body too large' } });
      return;
    }
    // Fastify rate-limit sets 429.
    if ((err as { statusCode?: number }).statusCode === 429) {
      reply
        .status(429)
        .send({ error: { code: 'rate_limited', message: 'Too many requests' } });
      return;
    }
    // Body parse / validation errors from Fastify.
    if ((err as { statusCode?: number }).statusCode === 400) {
      reply.status(400).send({ error: { code: 'validation_error', message: 'Invalid request' } });
      return;
    }

    if (isAppError(err)) {
      const body: { error: { code: string; message: string; details?: unknown } } = {
        error: { code: err.code, message: err.message },
      };
      if (err instanceof ValidationError && err.details !== undefined) {
        body.error.details = err.details;
      }
      reply.status(err.statusCode).send(body);
      return;
    }

    logger.error({ event: 'unhandled_error', reqId: req.id, err: (err as Error).name }, 'unhandled error');
    reply.status(500).send({ error: { code: 'internal_error', message: 'Internal server error' } });
  });

  app.setNotFoundHandler((_req, reply) => {
    reply.status(404).send({ error: { code: 'validation_error', message: 'Not found' } });
  });

  // Health endpoint: no auth, no secrets.
  app.get('/health', async (_req, reply) => {
    return reply.status(200).send({
      status: 'ok',
      provider: config.effectiveProvider,
      idempotencyEntries: idempotency.size,
    });
  });

  // Auth guard reused by protected routes.
  const requireAuth = (req: FastifyRequest): string => {
    const token = extractBearer(req.headers.authorization);
    if (!token || !safeEqual(token, config.deviceAuthToken)) {
      throw new UnauthorizedError();
    }
    return token;
  };

  app.post('/v1/answers', async (req: FastifyRequest, reply: FastifyReply) => {
    requireAuth(req);

    const parsed = answerRequestSchema.safeParse(req.body);
    if (!parsed.success) {
      const details = parsed.error.issues.map((i) => ({
        path: i.path.join('.'),
        message: i.message,
      }));
      throw new ValidationError('Request failed validation', details);
    }
    const body = parsed.data;

    // Idempotency: reserve the request id. Duplicate live ids get the stored
    // result or a conflict for still-pending ones.
    const existing = idempotency.get(body.requestId);
    if (existing) {
      if (existing.state === 'done') {
        return reply.status(200).send(existing.value);
      }
      // pending duplicate
      throw new AppError(409, 'idempotency_conflict', 'Request already in progress');
    }
    idempotency.reservePending(body.requestId);

    const ac = new AbortController();
    // IncomingMessage `close` can fire after the request body is consumed, well
    // before an async answer is ready. Observe the response socket instead and
    // abort only when it closes before a response was fully written.
    const onClose = (): void => {
      if (!reply.raw.writableEnded) ac.abort();
    };
    reply.raw.on('close', onClose);

    try {
      const result = await provider.generate(
        {
          question: body.question,
          locale: body.locale,
          maxWords: body.maxWords,
          requestId: body.requestId,
          signal: ac.signal,
        },
        logger,
      );

      const response: AnswerResponse = {
        requestId: body.requestId,
        answer: result.answer,
        words: result.words,
        locale: body.locale,
        provider: provider.kind,
      };
      idempotency.complete(body.requestId, response);
      logger.info(
        { event: 'answer_ok', reqId: req.id, requestId: body.requestId, provider: provider.kind, words: result.words },
        'answer generated',
      );
      return reply.status(200).send(response);
    } catch (err) {
      // Release the pending reservation so a client retry can proceed.
      idempotency.release(body.requestId);
      if (isAppError(err)) throw err;
      logger.error(
        { event: 'answer_error', reqId: req.id, requestId: body.requestId, err: (err as Error).name },
        'answer generation failed',
      );
      throw new AppError(502, 'provider_failed', 'Answer provider failed');
    } finally {
      reply.raw.removeListener('close', onClose);
    }
  });

  return { app, idempotency };
}
