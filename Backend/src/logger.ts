import { pino, type Logger } from 'pino';

/**
 * Structured logging with hard redaction. We never log the question, answer,
 * device token, or API key. Redaction is defense-in-depth: log call sites are
 * written to omit sensitive values, and pino's redact removes any that slip in
 * by known key names.
 */

const REDACT_PATHS = [
  'question',
  'answer',
  'token',
  'authorization',
  'apiKey',
  'openrouterApiKey',
  'deviceAuthToken',
  'prompt',
  'stdin',
  '*.question',
  '*.answer',
  '*.token',
  '*.authorization',
  '*.apiKey',
  'req.headers.authorization',
  'req.body.question',
];

export function createLogger(level: string): Logger {
  return pino({
    level,
    redact: {
      paths: REDACT_PATHS,
      censor: '[redacted]',
    },
    base: { service: 'living-page-backend' },
    timestamp: pino.stdTimeFunctions.isoTime,
    formatters: {
      level(label) {
        return { level: label };
      },
    },
  });
}

export type { Logger };
