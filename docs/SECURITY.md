# Living Page — Security model

This document describes the trust boundaries, the exact data that crosses them,
and the protections in place. It reflects the **prototype** as implemented; it
does not describe a production, multi-user, or hosted system.

## Threat boundaries

```
┌─ Boundary A: on-device ─────────────────┐
│ Raw Apple Pencil ink, PKDrawings,       │   never crosses any boundary
│ personal handwriting profile, progress  │
└─────────────────────────────────────────┘
                │  (only the four fields below)
                ▼
┌─ Boundary B: device ⇄ backend (network) ┐
│ HTTPS (prod) / loopback HTTP (Simulator)│   Authorization: Bearer <device token>
└─────────────────────────────────────────┘
                │
                ▼
┌─ Boundary C: backend ⇄ Kiro CLI ────────┐
│ Prompt over stdin to an isolated,       │   KIRO_API_KEY server-only
│ zero-tool agent (shell:false)           │
└─────────────────────────────────────────┘
```

## Data inventory

### Crosses the network (device → backend): exactly four fields

| Field       | Type   | Notes                                            |
|-------------|--------|--------------------------------------------------|
| `requestId` | string | lowercase UUID                                   |
| `question`  | string | the **confirmed recognized** text, trimmed       |
| `locale`    | string | one of `en`, `en-US`, `en-GB`, `en-AU`, `en-CA`  |
| `maxWords`  | number | integer 1–120 (answer-length limit)              |

Enforced on both sides: the Swift `AnswerRequest` has a hand-written `Encodable`
that emits only these four keys (`iPadApp/Sources/Networking/AnswerWireModels.swift`),
and the backend uses a **strict** Zod schema that rejects unknown keys
(`Backend/src/schema.ts`). There is no code path that serializes a `PKDrawing`,
stroke geometry, timing, force/tilt, or a `HandwritingProfile` into the request.

### Stays local to the device (never transmitted)

- Raw Apple Pencil ink and `PKDrawing`s (question and rendered answer).
- The personal handwriting profile (`profile.json`) and calibration progress
  (`progress.json`) in `Application Support/Handwriting/`, written atomically
  with iOS data protection and excluded from backup.
- Selected style preference.

### Server-only (never sent to the device)

- `KIRO_API_KEY` — held only in the backend environment; used solely to reach
  Kiro. It is never returned in responses and never logged.

## Protections

- **Device bearer token.** The device presents `Authorization: Bearer <token>`.
  The backend compares it to `DEVICE_AUTH_TOKEN` with a constant-time comparison.
  **Limitations:** this is a single shared device secret, not per-user identity;
  it authenticates "a configured device," not a person. It is stored in the iOS
  Keychain (`...AfterFirstUnlockThisDeviceOnly`) and must be ≥ 16 characters on
  both sides. It is never logged or displayed.
- **Process isolation of Kiro.** The backend spawns `kiro-cli` **directly** with
  an argv array (`shell: false`), passes the entire prompt via **stdin** (never
  argv), and runs a generated `living-page` custom agent with `tools: []`, no MCP
  servers/Powers, no resources, and a deny-all policy. `HOME` and `KIRO_HOME`
  point at a disposable temp workspace so global config cannot enter the request.
- **TLS.** Production/physical-device traffic must use HTTPS. The Simulator may
  use loopback cleartext (`http://localhost`) only; the app rejects remote
  cleartext URLs. ATS `NSAllowsLocalNetworking` permits local hosts but does not
  enable arbitrary internet cleartext.
- **Logging.** Structured logs never include the question, answer, token, or
  key. Only controlled fields (event, request id, method, route, status,
  provider, word count) are logged.
- **Idempotency & rate limits.** Requests are keyed by `requestId` in a bounded
  in-memory store (TTL + capacity eviction): a duplicate completed request
  replays the stored result, an in-flight duplicate gets `409`, and a failure
  releases the reservation for retry. Rate limiting is per device-token
  fingerprint (or per IP), with configurable window and max.
- **Response validation.** The app validates each `200` body against the request
  it sent (matching `requestId`, expected `locale`, non-empty answer, `words`
  within `1...maxWords`, known provider) before accepting it; violations map to a
  malformed-response error rather than a displayed answer.

## Single-instance limitation

Idempotency and rate-limit state are **in-memory in a single process**. Running
multiple backend instances (or restarting) loses this state and breaks
cross-instance idempotency/rate limiting. There is no shared/persistent store in
this prototype.

## Credential rotation

- Rotate the **device token** by launching the app once with
  `LIVINGPAGE_RESET_DEVICE_CREDENTIAL=1` and a new
  `LIVINGPAGE_BOOTSTRAP_TOKEN` (≥ 16 chars), and updating the backend
  `DEVICE_AUTH_TOKEN` to the same value. Ordinary launches never overwrite the
  stored credential.
- Rotate the **Kiro key** by replacing `KIRO_API_KEY` in the backend environment
  and restarting.

## Incident steps

1. **Suspected device-token compromise:** change `DEVICE_AUTH_TOKEN` on the
   backend and restart; rotate the device credential (reset flow above). Old
   tokens immediately fail auth.
2. **Suspected Kiro key compromise:** revoke/rotate the key at the provider,
   update `KIRO_API_KEY`, restart. Optionally set `PROVIDER=mock` to disable the
   real provider while investigating.
3. **Abuse / runaway traffic:** lower `RATE_LIMIT_MAX` / tighten
   `RATE_LIMIT_WINDOW_MS`, or stop the instance.
4. **Review logs** (which contain no secrets or content) for the affected
   `requestId`/route/status.

## Non-goals (explicitly out of scope)

- **Not** multi-user or production-grade authentication/authorization; a single
  shared device token is not user identity.
- **No** handwriting signature collection or generation.
- **No** export of generated handwriting.
- **No** cloud deployment or hosted infrastructure is created.
- **No** persistence of drawings or profiles off-device.
