import { buildApp } from './app.js';
import { loadConfig } from './config.js';
import { createLogger } from './logger.js';

async function main(): Promise<void> {
  const config = loadConfig();
  const logger = createLogger(config.logLevel);

  logger.info(
    {
      event: 'startup',
      provider: config.effectiveProvider,
      port: config.port,
      nodeEnv: config.nodeEnv,
    },
    'starting living-page-backend',
  );

  const { app, idempotency } = await buildApp({ config, logger });

  // Periodic sweep of expired idempotency entries.
  const sweepTimer = setInterval(() => idempotency.sweep(), Math.min(config.idempotencyTtlMs, 60_000));
  sweepTimer.unref();

  await app.listen({ host: config.host, port: config.port });
  logger.info({ event: 'listening', host: config.host, port: config.port }, 'listening');

  let shuttingDown = false;
  const shutdown = async (sig: string): Promise<void> => {
    if (shuttingDown) return;
    shuttingDown = true;
    logger.info({ event: 'shutdown', signal: sig }, 'shutting down gracefully');
    clearInterval(sweepTimer);
    try {
      // Stop accepting new connections; wait for in-flight to drain.
      await app.close();
      logger.info({ event: 'shutdown_complete' }, 'shutdown complete');
      process.exit(0);
    } catch (err) {
      logger.error({ event: 'shutdown_error', err: (err as Error).name }, 'shutdown error');
      process.exit(1);
    }
  };

  process.on('SIGTERM', () => void shutdown('SIGTERM'));
  process.on('SIGINT', () => void shutdown('SIGINT'));
}

main().catch((err: unknown) => {
  // Avoid logging secrets: only the error name/message (which our own errors
  // keep safe). Config errors here are about missing/invalid env, not values.
  const message = err instanceof Error ? err.message : 'unknown startup error';
  process.stderr.write(`fatal: ${message}\n`);
  process.exit(1);
});
