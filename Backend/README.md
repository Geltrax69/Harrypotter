# Living Page — Backend

Secure TypeScript service that brokers a single confirmed, recognized question
into a concise Kiro-generated answer for the Living Page iPad app.

Only four fields ever cross the network from the device: the confirmed
recognized `question`, a `locale`, a `requestId`, and an answer-length limit
`maxWords`. No stroke data, timing, or personal handwriting profile is accepted.

## Related docs

- Repo overview & quick start: [`../README.md`](../README.md)
- iPad app setup & operations: [`../iPadApp/README.md`](../iPadApp/README.md)
- API request/response/errors + curl: [`../docs/API.md`](../docs/API.md)
- Security model & data inventory: [`../docs/SECURITY.md`](../docs/SECURITY.md)
- Physical-device validation: [`../docs/PHYSICAL_DEVICE_CHECKLIST.md`](../docs/PHYSICAL_DEVICE_CHECKLIST.md)

## Requirements

- Node.js **>= 20.6** (uses the built-in `--env-file`, so no `dotenv`).
- The real provider additionally needs the `kiro-cli` binary on `PATH` (or set
  `KIRO_CLI_PATH`) and a `KIRO_API_KEY`. Until a key is supplied the service runs
  in deterministic **mock mode**.

## Quick start

```bash
npm install
cp .env.example .env        # fill DEVICE_AUTH_TOKEN (>=16 chars)
npm run typecheck
npm test
npm run build
npm start                   # loads .env via node --env-file
```

Health check:

```bash
curl -s localhost:8080/health
```

Ask a question (mock mode):

```bash
curl -s localhost:8080/v1/answers \
  -H "authorization: Bearer $DEVICE_AUTH_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"requestId":"00000000-0000-4000-8000-000000000001",
       "question":"What is a good use of a quiet page?",
       "locale":"en","maxWords":40}'
```

## API

### `GET /health`
No auth. Returns `{ status, provider, idempotencyEntries }`.

### `POST /v1/answers`
Bearer auth with the device token (`DEVICE_AUTH_TOKEN`).

Request body (strict schema, unknown keys rejected):

| field       | type   | rules                                             |
|-------------|--------|---------------------------------------------------|
| `requestId` | string | UUID                                              |
| `question`  | string | trimmed, non-empty, ≤ 2000 chars                  |
| `locale`    | string | one of `en`, `en-US`, `en-GB`, `en-AU`, `en-CA`   |
| `maxWords`  | number | integer, 1–120                                    |

Response `200`:

```json
{ "requestId": "...", "answer": "...", "words": 12, "locale": "en", "provider": "mock" }
```

Errors are typed JSON: `{ "error": { "code": "...", "message": "..." } }` with
codes `validation_error` (400), `unauthorized` (401), `idempotency_conflict`
(409), `payload_too_large` (413), `rate_limited` (429), `provider_failed` (502),
`provider_unavailable` (503), `provider_timeout` (504), `internal_error` (500).

## Providers

An `AnswerProvider` adapter interface decouples routing from the answer source,
so the CLI provider can later be swapped for a REST provider with no route
changes.

- **MockAnswerProvider** — deterministic, offline. Same input → same answer.
- **KiroCliAnswerProvider** — invokes `kiro-cli chat --v3 --no-interactive
  --output-format stream-json --trust-tools=`.

### Kiro provider security posture

- Spawns the binary **directly** with an argv array (`shell: false`) — never via
  a shell, so the question can never be interpreted as a command.
- Passes the **entire prompt through stdin**, never argv (stays out of the
  process table).
- Creates a disposable **`KIRO_HOME`** inside the fresh temp directory and writes one explicit `living-page` custom agent with `tools: []`, no MCP servers or Powers, no resources, and a deny-all capability policy. The CLI receives `--agent living-page --trust-tools=` as defense in depth.
- Sets both `HOME` and `KIRO_HOME` to that disposable workspace so global agents, steering, skills, hooks, sessions, and user configuration cannot enter the request.
- **Serializes** to one concurrent subprocess (mutex).
- Enforces a **wall-clock timeout** and **stdout/stderr byte caps**; on breach it
  sends `SIGTERM` then `SIGKILL` and cleans up.
- Robustly parses the **stream-json** JSON Lines, extracting the final assistant
  text; **rejects** interruptions, error events, non-zero exits, malformed or
  empty output.
- **Caps** the normalized plain-text answer by words.

## Security & operations

- Bearer device-token auth with constant-time comparison.
- Per-token (fingerprinted) / per-IP rate limiting.
- Security headers via `@fastify/helmet`.
- JSON body size limit.
- **Redacted structured logs**: never log question, answer, token, or key
  values (enforced by call-site discipline plus `pino` redaction).
- **Bounded in-memory idempotency** by `requestId` (TTL + capacity eviction);
  duplicate completed requests replay the stored result, in-flight duplicates
  get `409`, failures release the reservation for retry.
- Graceful shutdown on `SIGTERM`/`SIGINT` (drains in-flight requests).
- Typed errors and safe client payloads.

## Configuration

All configuration is environment-based and validated at startup (see
`src/config.ts`). See `.env.example` for the full list. Notably:

- `DEVICE_AUTH_TOKEN` (required, ≥16 chars)
- `PROVIDER` = `mock` | `kiro` (defaults to mock; stays mock without a key)
- `KIRO_API_KEY` (server-only; blank ⇒ mock mode)
- `KIRO_TIMEOUT_MS`, `KIRO_MAX_STDOUT_BYTES`, `KIRO_MAX_STDERR_BYTES`
- `BODY_LIMIT_BYTES`, `RATE_LIMIT_MAX`, `RATE_LIMIT_WINDOW_MS`
- `IDEMPOTENCY_MAX_ENTRIES`, `IDEMPOTENCY_TTL_MS`

## Scripts

| script              | purpose                                          |
|---------------------|--------------------------------------------------|
| `npm run typecheck` | strict `tsc --noEmit`                            |
| `npm test`          | full test suite (`node --test`)                  |
| `npm run build`     | compile to `dist/`                               |
| `npm start`         | run compiled server with `--env-file=.env`       |
| `npm run dev`       | watch-mode dev server                            |
| `npm run smoke:real`| gated real Kiro smoke (needs `SMOKE_REAL=1` + key) |

## Docker

```bash
docker build -t living-page-backend .
docker run --rm -p 8080:8080 \
  -e DEVICE_AUTH_TOKEN=... -e PROVIDER=mock \
  living-page-backend
```

`kiro-cli` is not installed in the image; mount/install it and set
`KIRO_CLI_PATH` + `KIRO_API_KEY` to enable the real provider.

## Deployment & connectivity notes

- **Kiro subscription required for the real provider.** The `kiro` provider needs
  an **eligible Kiro account / API key** (`KIRO_API_KEY`). Without a key the
  service stays in deterministic **mock mode** by design, so the app is usable
  before credentials exist. No real Kiro smoke has been run here; the gated
  `npm run smoke:real` is intentionally **not** executed.
- **Generated, isolated, zero-tool agent.** The Kiro provider writes a disposable
  `living-page` custom agent with `tools: []`, no MCP servers/Powers, no
  resources, and a deny-all policy into a temp `KIRO_HOME`/`HOME`, and invokes the
  CLI with `--agent living-page --trust-tools=`. Global agents, steering, skills,
  hooks, and sessions cannot enter a request.
- **Host vs. Docker limitation.** The real provider requires the `kiro-cli`
  binary and a usable auth context on the machine that runs the process. The
  provided Docker image does **not** bundle `kiro-cli`; to use `kiro` in a
  container you must mount/install the binary and supply `KIRO_CLI_PATH` +
  `KIRO_API_KEY`. Running on the host (where `kiro-cli` is already on `PATH`) is
  the simpler path for the prototype.
- **HTTPS reverse proxy for a physical device.** This service speaks plain HTTP.
  The Simulator can reach it at `http://localhost:8080`, but a **physical iPad
  requires HTTPS** — put the service behind a local TLS-terminating reverse proxy
  and point `LIVINGPAGE_BASE_URL` at the `https://` origin. The app rejects
  remote cleartext URLs.
- **Single-instance state.** Idempotency and rate-limit state are in-memory in a
  single process; running multiple instances is not supported in this prototype
  (see [`../docs/SECURITY.md`](../docs/SECURITY.md)).
- **No cloud deployment** is created by this project; hosting remains undecided.
