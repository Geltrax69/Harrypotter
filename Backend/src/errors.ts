/**
 * Typed application errors. Each carries an HTTP status and a stable machine
 * `code`. Messages here are safe for logs and clients: they never contain the
 * question, answer, token, or API key values.
 */

export type ErrorCode =
  | 'validation_error'
  | 'unauthorized'
  | 'rate_limited'
  | 'idempotency_conflict'
  | 'provider_timeout'
  | 'provider_failed'
  | 'provider_unavailable'
  | 'payload_too_large'
  | 'internal_error';

export class AppError extends Error {
  public readonly statusCode: number;
  public readonly code: ErrorCode;
  public readonly details?: unknown;

  public constructor(
    statusCode: number,
    code: ErrorCode,
    message: string,
    details?: unknown,
  ) {
    super(message);
    this.name = new.target.name;
    this.statusCode = statusCode;
    this.code = code;
    if (details !== undefined) {
      this.details = details;
    }
    Error.captureStackTrace?.(this, new.target);
  }
}

export class ValidationError extends AppError {
  public constructor(message: string, details?: unknown) {
    super(400, 'validation_error', message, details);
  }
}

export class UnauthorizedError extends AppError {
  public constructor(message = 'Missing or invalid device token') {
    super(401, 'unauthorized', message);
  }
}

export class RateLimitError extends AppError {
  public constructor(message = 'Too many requests') {
    super(429, 'rate_limited', message);
  }
}

export class PayloadTooLargeError extends AppError {
  public constructor(message = 'Request body too large') {
    super(413, 'payload_too_large', message);
  }
}

export class ProviderTimeoutError extends AppError {
  public constructor(message = 'Answer provider timed out') {
    super(504, 'provider_timeout', message);
  }
}

export class ProviderFailedError extends AppError {
  public constructor(message = 'Answer provider failed', details?: unknown) {
    super(502, 'provider_failed', message, details);
  }
}

export class ProviderUnavailableError extends AppError {
  public constructor(message = 'Answer provider unavailable') {
    super(503, 'provider_unavailable', message);
  }
}

export function isAppError(err: unknown): err is AppError {
  return err instanceof AppError;
}
