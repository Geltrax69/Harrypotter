# Living Page

Living Page is a single-page, Apple Pencil-first question-and-answer notebook for
iPad. You handwrite one question, confirm its on-device recognition, and a
concise answer writes itself below the question as genuine vector ink — in a
preset "hand" or a style derived from your own Apple Pencil samples. The answer
is display-only after it appears. Raw
handwriting and the personal style profile never leave the device; only a small
confirmed request crosses the network.

## Current status (honest)

This is a **local prototype**, not a shipped product.

- The iPad app builds and its unit tests pass on the iOS 27 Simulator.
- The backend runs in deterministic **mock mode** out of the box and passes its
  test suite, typecheck, and build.
- **No real Kiro credential, endpoint, hosting, logo, font, or handwriting
  dataset has been supplied.** The real Kiro path is implemented but
  **environment-gated and unverified end to end** — no real Kiro smoke has been
  run.
- **Physical-device behavior is unverified.** Everything device-specific
  (Pencil-only input, file protection, Keychain, live network) is gated behind
  the checklist in `docs/PHYSICAL_DEVICE_CHECKLIST.md` and has not been claimed
  as validated.
- Hosting is deliberately undecided; no cloud infrastructure is created.

## Monorepo map

```
LivingPage/
├── PRODUCT.md                     Product definition and principles
├── README.md                      This file
├── .gitignore                     Root ignore policy (env, build, generated project)
├── docs/
│   ├── API.md                     POST /v1/answers request/response/errors + curl
│   ├── SECURITY.md                Threat boundaries and data inventory
│   └── PHYSICAL_DEVICE_CHECKLIST.md  Reproducible on-device validation steps
├── Backend/                       TypeScript Fastify service (mock | Kiro CLI broker)
│   ├── src/                       app, config, schema, providers, util
│   ├── test/                      node --test suites
│   ├── scripts/smoke-real.ts      GATED real-Kiro smoke (not run here)
│   ├── .env.example               Placeholder env template (no real values)
│   └── README.md                  Backend setup & operations
└── iPadApp/                       SwiftUI/PencilKit iPad app
    ├── project.yml                XcodeGen source of truth (generates .xcodeproj)
    ├── Sources/                   App, Networking, Ink, Recognition, Calibration, UI
    ├── Tests/                     Swift Testing unit tests
    ├── UITests/                   XCUITest UI tests
    └── README.md                  iPad app setup & operations
```

## Architecture & data flow

```
┌─────────────────────────── iPad (device) ───────────────────────────┐
│  Apple Pencil ink → PencilKit on-device recognition → inline confirm │
│  Confirmed text + locale + requestId + maxWords  ─────────┐          │
│  Drawings & personal handwriting profile stay LOCAL       │          │
│  (Application Support, file-protected, backup-excluded)   │          │
└───────────────────────────────────────────────────────────┼─────────┘
                                                              │ HTTPS (prod) /
                                                              │ loopback HTTP (Simulator)
                                                              │ Authorization: Bearer <device token>
                                                              ▼
┌─────────────────────── Backend (TypeScript) ────────────────────────┐
│  POST /v1/answers → auth → strict schema → idempotency → provider    │
│  MockAnswerProvider (default)  OR  KiroCliAnswerProvider (gated)      │
│  KIRO_API_KEY is SERVER-ONLY and never sent to the device            │
└───────────────────────────────────────────────────────────┬─────────┘
                                                              │ stdin prompt, zero-tool
                                                              │ isolated agent, shell:false
                                                              ▼
                                                        Kiro CLI (headless)
```

Only four fields ever leave the device: `requestId`, `question`, `locale`,
`maxWords`. See `docs/API.md` and `docs/SECURITY.md`.

## Prerequisites

- **Xcode** with the **iPadOS 27** SDK/Simulator runtime installed.
- An **Apple Pencil** and a compatible iPad — required only for physical-device
  testing (the Simulator flow uses injected synthetic input).
- **Node.js 20** (≥ 20.6; uses the built-in `--env-file`, no `dotenv`).
- **XcodeGen** (`brew install xcodegen`) — the `.xcodeproj` is generated.
- An **eligible Kiro account / API key** — required only to exercise the real
  provider. The prototype is fully usable in mock mode without one.

## Quick start — mock backend + iPad Simulator

1. Start the backend in mock mode:

   ```bash
   cd Backend
   npm install
   cp .env.example .env          # set DEVICE_AUTH_TOKEN to a ≥16-char value
   npm start                     # serves http://localhost:8080 in mock mode
   ```

2. Generate and open the iPad app:

   ```bash
   cd ../iPadApp
   xcodegen generate
   open LivingPage.xcodeproj
   ```

3. Select an **iPad simulator running iOS 27** and Run. On the Simulator the
   default base URL is `http://localhost:8080` (loopback cleartext is allowed
   for development only). Bootstrap a device token via the Run scheme
   environment variables below.

## Xcode Run scheme environment variables

Set these under **Product → Scheme → Edit Scheme… → Run → Arguments →
Environment Variables**. None are committed; none contain real secrets.

| Variable                              | Purpose                                                                 |
|---------------------------------------|-------------------------------------------------------------------------|
| `LIVINGPAGE_BASE_URL`                 | Backend origin. HTTPS anywhere; cleartext HTTP only for `localhost`/`127.0.0.1`/`::1`. Invalid/remote-cleartext/credentialed URLs safely fall back to `http://localhost:8080`. |
| `LIVINGPAGE_BOOTSTRAP_TOKEN`          | One-time device bearer token to persist into the Keychain. Must be **≥ 16 chars**. Ignored if a credential already exists (unless resetting). |
| `LIVINGPAGE_RESET_DEVICE_CREDENTIAL`  | Set to `1` for a **single** launch to clear the stored credential and re-bootstrap from `LIVINGPAGE_BOOTSTRAP_TOKEN`. Remove afterward. |

The device token is never logged, printed, or shown in UI. Ordinary launches
never overwrite an existing credential.

### Exact token-name mapping

The device token the app presents and the backend token it is checked against
must be the **same value**, configured under different names on each side:

| Side     | Name                          | Where set                                  |
|----------|-------------------------------|--------------------------------------------|
| iPad app | `LIVINGPAGE_BOOTSTRAP_TOKEN`  | Xcode Run scheme env (one-time bootstrap)  |
| Backend  | `DEVICE_AUTH_TOKEN`           | `Backend/.env` (loaded via `--env-file`)   |

`LIVINGPAGE_BOOTSTRAP_TOKEN` (device) **must equal** `DEVICE_AUTH_TOKEN`
(server). The Kiro key (`KIRO_API_KEY`) is **server-only** and is never placed
on the device.

## Switching to the real Kiro provider

Real Kiro requires an eligible account and is **not verified here**.

1. In `Backend/.env`, set `PROVIDER=kiro` and supply `KIRO_API_KEY` (and, if
   needed, `KIRO_CLI_PATH` / `KIRO_MODEL`). Without a key the service stays in
   mock mode by design.
2. The gated smoke script exists but is intentionally **not run** in this task:

   ```bash
   # Requires SMOKE_REAL=1 and a real key in .env. NOT run here.
   cd Backend && SMOKE_REAL=1 npm run smoke:real
   ```

## Test commands

```bash
# Backend
cd Backend && npm run typecheck && npm test && npm run build

# iPad app (iOS 27 Simulator; pick a booted/available iOS 27 iPad)
cd iPadApp && xcodegen generate
xcodebuild test -project LivingPage.xcodeproj -scheme LivingPage \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
  -only-testing:LivingPageTests
```

## No-secret rules

- Never commit real tokens, keys, endpoints, or `.env` files. Only `*.env.example`
  templates are tracked.
- `KIRO_API_KEY` is server-only; it never appears on the device or in the app.
- The device bearer token is never logged or displayed.
- Placeholders in docs (e.g. `REPLACE_WITH_...`, `$DEVICE_AUTH_TOKEN`) are not
  real values.

## Known physical-device gates

None of the following are validated; see `docs/PHYSICAL_DEVICE_CHECKLIST.md`:

- Pencil-only question input with finger-only scrolling.
- Idle-pause recognition (~1.5s), cancel, and stale-recognition handling.
- Handwriting recognition error rate targets.
- Real Apple Pencil force/tilt capture and per-stroke render state.
- File-protection and Keychain behavior on real hardware.
- Live network, retry, and offline recovery against a reachable backend over
  **HTTPS** (a physical iPad requires HTTPS; loopback cleartext is Simulator-only).
- Dark mode, VoiceOver, Reduce Motion, and rotation on device.
