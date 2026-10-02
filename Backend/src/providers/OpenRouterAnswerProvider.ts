import type { AppConfig } from '../config.js';
import { ProviderFailedError, ProviderTimeoutError } from '../errors.js';
import type { Logger } from '../logger.js';
import { capWords, countWords, normalizePlainText } from '../text.js';
import type {
  AnswerProvider,
  AnswerProviderInput,
  AnswerProviderResult,
} from './AnswerProvider.js';
import { buildPrompt } from './prompt.js';

const ENDPOINT = 'https://openrouter.ai/api/v1/chat/completions';

/**
 * Provider that calls OpenRouter's chat completions API over HTTPS.
 *
 * `OPENROUTER_MODEL` may be a comma-separated list: OpenRouter tries them in
 * order, so a rate-limited free model falls through to the next one.
 * The API key is sent only in the Authorization header and is never logged.
 */
export class OpenRouterAnswerProvider implements AnswerProvider {
  public readonly kind = 'openrouter' as const;

  public constructor(private readonly config: AppConfig) {}

  public async generate(
    input: AnswerProviderInput,
    logger: Logger,
  ): Promise<AnswerProviderResult> {
    const models = this.config.openrouterModels;
    let res: Response;
    try {
      res = await fetch(ENDPOINT, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${this.config.openrouterApiKey}`,
          'Content-Type': 'application/json',
          'X-Title': 'Living Page',
        },
        body: JSON.stringify({
          ...(models.length > 1 ? { models } : { model: models[0] }),
          messages: [{ role: 'user', content: buildPrompt(input) }],
          max_tokens: 400,
          // Thinking makes free models take 30s+; a page answer doesn't need it.
          reasoning: { enabled: false },
        }),
        signal: AbortSignal.any([
          input.signal,
          AbortSignal.timeout(this.config.openrouterTimeoutMs),
        ]),
      });
    } catch (err) {
      if (err instanceof Error && err.name === 'TimeoutError') {
        throw new ProviderTimeoutError();
      }
      throw new ProviderFailedError('provider request failed');
    }

    if (!res.ok) {
      logger.warn({ event: 'openrouter_http_error', status: res.status }, 'openrouter error');
      throw new ProviderFailedError(`provider returned ${res.status}`);
    }

    const body = (await res.json().catch(() => null)) as {
      model?: string;
      choices?: { message?: { content?: unknown } }[];
    } | null;
    const content = body?.choices?.[0]?.message?.content;
    const answer = capWords(
      normalizePlainText(typeof content === 'string' ? content : ''),
      input.maxWords,
    );
    if (answer.length === 0) {
      throw new ProviderFailedError('provider produced empty answer');
    }
    logger.info({ event: 'openrouter_ok', model: body?.model }, 'openrouter answered');
    return { answer, words: countWords(answer) };
  }
}
