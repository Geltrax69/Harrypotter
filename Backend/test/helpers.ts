import { loadConfig, type AppConfig } from '../src/config.js';

export const TEST_TOKEN = 'test-device-token-abcdef123456';

export function testConfig(overrides: Partial<NodeJS.ProcessEnv> = {}): AppConfig {
  const env: NodeJS.ProcessEnv = {
    NODE_ENV: 'test',
    PORT: '0',
    DEVICE_AUTH_TOKEN: TEST_TOKEN,
    PROVIDER: 'mock',
    LOG_LEVEL: 'silent',
    RATE_LIMIT_MAX: '1000',
    RATE_LIMIT_WINDOW_MS: '60000',
    ...overrides,
  };
  return loadConfig(env);
}

export function uuid(n = 1): string {
  const s = n.toString(16).padStart(12, '0');
  return `00000000-0000-4000-8000-${s}`;
}
