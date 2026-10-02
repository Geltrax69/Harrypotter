import type { AppConfig } from '../config.js';
import type { AnswerProvider } from './AnswerProvider.js';
import { OpenRouterAnswerProvider } from './OpenRouterAnswerProvider.js';
import { MockAnswerProvider } from './MockAnswerProvider.js';

export function createProvider(config: AppConfig): AnswerProvider {
  if (config.effectiveProvider === 'openrouter') {
    return new OpenRouterAnswerProvider(config);
  }
  return new MockAnswerProvider();
}
