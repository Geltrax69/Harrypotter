import { z } from 'zod';

/**
 * Environment parsing. No dotenv dependency: production/dev load env via
 * `node --env-file=.env`. This module only validates and coerces.
 *
 * Provider selection:
 *  - If OPENROUTER_API_KEY is absent/empty, the service runs in deterministic
 *    mock mode regardless of PROVIDER, so the app is usable before real
 *    credentials are supplied.
 *  - If PROVIDER=openrouter and the key is present, OpenRouter answers.
 */

const boolFromString = z
  .enum(['true', 'false', '1', '0'])
  .transform((v) => v === 'true' || v === '1');

const rawSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().min(0).max(65535).default(8080),
  HOST: z.string().min(1).default('0.0.0.0'),

  // Auth: device bearer token the iPad app presents. Required to start.
  DEVICE_AUTH_TOKEN: z
    .string()
    .min(16, 'DEVICE_AUTH_TOKEN must be at least 16 characters'),

  // Provider selection and OpenRouter settings.
  PROVIDER: z.enum(['mock', 'openrouter']).default('mock'),
  OPENROUTER_API_KEY: z.string().optional(),
  // Comma-separated; later entries are fallbacks if earlier ones are rate-limited.
  OPENROUTER_MODEL: z.string().min(1).default('inclusionai/ling-3.0-flash-sante:free,dots-studio/dots-3-note-preview:free'),
  OPENROUTER_TIMEOUT_MS: z.coerce.number().int().min(1000).max(120_000).default(30_000),

  // HTTP limits and rate limiting.
  BODY_LIMIT_BYTES: z.coerce.number().int().min(256).max(1_000_000).default(16_384),
  RATE_LIMIT_MAX: z.coerce.number().int().min(1).max(100_000).default(30),
  RATE_LIMIT_WINDOW_MS: z.coerce
    .number()
    .int()
    .min(1000)
    .max(3_600_000)
    .default(60_000),

  // Idempotency store bound.
  IDEMPOTENCY_MAX_ENTRIES: z.coerce
    .number()
    .int()
    .min(16)
    .max(1_000_000)
    .default(10_000),
  IDEMPOTENCY_TTL_MS: z.coerce
    .number()
    .int()
    .min(1000)
    .max(86_400_000)
    .default(600_000),

  LOG_LEVEL: z
    .enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent'])
    .default('info'),
  TRUST_PROXY: boolFromString.default('false'),
});

export type AppConfig = {
  nodeEnv: 'development' | 'test' | 'production';
  port: number;
  host: string;
  deviceAuthToken: string;
  provider: 'mock' | 'openrouter';
  /** Effective provider after considering OPENROUTER_API_KEY presence. */
  effectiveProvider: 'mock' | 'openrouter';
  openrouterApiKey: string | undefined;
  openrouterModels: string[];
  openrouterTimeoutMs: number;
  bodyLimitBytes: number;
  rateLimitMax: number;
  rateLimitWindowMs: number;
  idempotencyMaxEntries: number;
  idempotencyTtlMs: number;
  logLevel: string;
  trustProxy: boolean;
};

export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  const parsed = rawSchema.safeParse(env);
  if (!parsed.success) {
    const issues = parsed.error.issues
      .map((i) => `${i.path.join('.') || '(root)'}: ${i.message}`)
      .join('; ');
    throw new Error(`Invalid environment configuration: ${issues}`);
  }
  const e = parsed.data;

  const hasKey = typeof e.OPENROUTER_API_KEY === 'string' && e.OPENROUTER_API_KEY.length > 0;
  // Mock unless explicitly openrouter AND a key is present.
  const effectiveProvider: 'mock' | 'openrouter' =
    e.PROVIDER === 'openrouter' && hasKey ? 'openrouter' : 'mock';

  return {
    nodeEnv: e.NODE_ENV,
    port: e.PORT,
    host: e.HOST,
    deviceAuthToken: e.DEVICE_AUTH_TOKEN,
    provider: e.PROVIDER,
    effectiveProvider,
    openrouterApiKey: hasKey ? e.OPENROUTER_API_KEY : undefined,
    openrouterModels: e.OPENROUTER_MODEL.split(',').map((m) => m.trim()).filter(Boolean),
    openrouterTimeoutMs: e.OPENROUTER_TIMEOUT_MS,
    bodyLimitBytes: e.BODY_LIMIT_BYTES,
    rateLimitMax: e.RATE_LIMIT_MAX,
    rateLimitWindowMs: e.RATE_LIMIT_WINDOW_MS,
    idempotencyMaxEntries: e.IDEMPOTENCY_MAX_ENTRIES,
    idempotencyTtlMs: e.IDEMPOTENCY_TTL_MS,
    logLevel: e.LOG_LEVEL,
    trustProxy: e.TRUST_PROXY,
  };
}
