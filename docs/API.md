# Living Page — API

The backend exposes a health probe and a single answer endpoint. Only four
fields ever cross the network from the device. All examples use **placeholders
and environment variables — never real tokens or endpoints.**

Base URL (development): `http://localhost:8080`. On a physical device this must
be an **HTTPS** origin.

## Authentication

`POST /v1/answers` requires a bearer token:

```
Authorization: Bearer <DEVICE_AUTH_TOKEN>
```

The token must equal the backend `DEVICE_AUTH_TOKEN` (≥ 16 chars). `GET /health`
requires no auth.

## `GET /health`

No auth. Returns current provider and idempotency store size.

```json
{ "status": "ok", "provider": "mock", "idempotencyEntries": 0 }
```

```bash
curl -s "${BASE_URL:-http://localhost:8080}/health"
```

## `POST /v1/answers`

### Request body (strict — unknown keys rejected)

| field       | type   | rules                                             |
|-------------|--------|---------------------------------------------------|
| `requestId` | string | UUID (lowercase on the wire)                      |
| `question`  | string | trimmed, non-empty, ≤ 2000 chars                  |
| `locale`    | string | one of `en`, `en-US`, `en-GB`, `en-AU`, `en-CA`   |
| `maxWords`  | number | integer, 1–120                                    |

```json
{
  "requestId": "00000000-0000-4000-8000-000000000001",
  "question": "What is a good use of a quiet page?",
  "locale": "en",
  "maxWords": 40
}
```

### Response `200`

```json
{
  "requestId": "00000000-0000-4000-8000-000000000001",
  "answer": "…",
  "words": 12,
  "locale": "en",
  "provider": "mock"
}
```

`provider` is `mock` or `kiro`. The iPad client additionally validates that the
`requestId` and `locale` match the request, `answer` is non-empty, and
`words` is within `1...maxWords` before accepting the response.

### Errors

All errors share the shape `{ "error": { "code": "...", "message": "..." } }`
(validation errors may add `details`).

| Status | `code`                 | When                                            |
|--------|------------------------|-------------------------------------------------|
| 400    | `validation_error`     | Body fails the strict schema, or malformed JSON |
| 401    | `unauthorized`         | Missing/invalid bearer token                    |
| 409    | `idempotency_conflict` | Same `requestId` still in flight                |
| 413    | `payload_too_large`    | Body exceeds `BODY_LIMIT_BYTES`                 |
| 429    | `rate_limited`         | Rate limit exceeded (per token/IP)              |
| 502    | `provider_failed`      | Provider errored                                |
| 503    | `provider_unavailable` | Provider unavailable                            |
| 504    | `provider_timeout`     | Provider exceeded `KIRO_TIMEOUT_MS`             |
| 500    | `internal_error`       | Unexpected error                                |

Example error body:

```json
{ "error": { "code": "unauthorized", "message": "Missing or invalid device token" } }
```

## curl examples (placeholders / env vars only)

Set the environment first (do not paste real secrets on the command line):

```bash
export BASE_URL="http://localhost:8080"          # HTTPS origin on a physical device
export DEVICE_AUTH_TOKEN="REPLACE_WITH_LOCAL_DEV_TOKEN_MIN_16_CHARS"
```

Ask a question:

```bash
curl -s "$BASE_URL/v1/answers" \
  -H "authorization: Bearer $DEVICE_AUTH_TOKEN" \
  -H 'content-type: application/json' \
  -d '{
        "requestId": "00000000-0000-4000-8000-000000000001",
        "question": "What is a good use of a quiet page?",
        "locale": "en",
        "maxWords": 40
      }'
```

Idempotent retry (same `requestId` replays the stored result once completed):

```bash
curl -s "$BASE_URL/v1/answers" \
  -H "authorization: Bearer $DEVICE_AUTH_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"requestId":"00000000-0000-4000-8000-000000000001","question":"What is a good use of a quiet page?","locale":"en","maxWords":40}'
```

Unauthorized (no/invalid token) returns `401`:

```bash
curl -s -o /dev/null -w '%{http_code}\n' "$BASE_URL/v1/answers" \
  -H 'content-type: application/json' \
  -d '{"requestId":"00000000-0000-4000-8000-000000000002","question":"hi","locale":"en","maxWords":10}'
```
