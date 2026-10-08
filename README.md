# Living Page

> ## Status: 🟡 In Progress
>
> <progress value="65" max="100"></progress>
> **Progress: 65%** — iPad app and Fastify backend both build; core notebook flow exists but the vector-ink answer engine is orphaned, iPad tests don't compile, and no physical-device run has happened.

<p align="center">
  <img src="banner.webp" alt="Living Page banner" width="100%" />
</p>

![Swift](https://img.shields.io/badge/Swift-5.0-F05138?logo=swift&logoColor=white)
![TypeScript](https://img.shields.io/badge/TypeScript-3178C6?logo=typescript&logoColor=white)
![Fastify](https://img.shields.io/badge/Fastify-000000?logo=fastify&logoColor=white)

## What it is

Living Page is a monorepo for a Pencil-first Q&A notebook on iPad, backed by
a small Fastify/TypeScript API. You handwrite a question with Apple Pencil,
the app recognizes it on-device, and a concise AI-generated answer is written
below it as handwriting-style text. Raw handwriting and the personal style
profile never leave the device; only a small confirmed request crosses the
network (`POST /v1/answers` with bearer auth — 4 wire fields:
requestId/question/locale/maxWords). The backend ships a deterministic mock
answer provider by default and an OpenRouter provider gated by
`OPENROUTER_API_KEY`.

## What works (verified)

Verified by reading the code; the backend was also built and typechecked on
this machine (Swift can't be compiled here):

- ✅ Backend builds and typechecks — `npm install`, `npm run build`, `npm run typecheck` all pass on this machine
- ✅ Backend env validation — server refuses to start without `DEVICE_AUTH_TOKEN` (verified: `fatal: Invalid environment configuration: DEVICE_AUTH_TOKEN: Required`)
- ✅ Mock + OpenRouter answer providers with a provider factory (`Backend/src/providers/`) — read the code; OpenRouter path is a real REST client
- ✅ iPad app structure is complete: `PageViewModel` (phases: writing → confirming → rendering → answered), PencilKit input, on-device handwriting recognition hooks, HTTP answer client, calibration flow with personal handwriting profile, dark-mode gold-ink theme (`iPadApp/Sources/`)
- ✅ Notebook theming landed (commit `434d8db`): app icon, `#2b3e6f` cardboard-grain page, legibility fixes
- ⚠️ Backend test suite does **not** run on this machine — `npm test` crashes before any test executes because the deprecated `--loader ts-node/esm` setup is incompatible with Node v24 (toolchain issue, not a test assertion)
- ⚠️ Known gaps found in code (all unverified-on-device):
  - The vector-ink answer engine (`Sources/Ink/AnswerComposer`, `InkStrokeBuilder`, `AnswerInkAnimator`, `BaseAlphabet`) is fully built but **orphaned** — live answers render as bundled-font text via `InkCanvasView`'s `AnswerFont`, not as generated ink strokes
  - The iPad unit tests and UI tests **don't compile against the current sources** (e.g. tests pass `styleSettings`/`profileStore`/`animator` args that `PageViewModel.init` no longer takes; stale `ScrollSyncCoordinator` references)
  - `Backend/README.md` documents a **Kiro CLI answer provider** that does not exist in code — the factory only has `mock` and `openrouter`
  - Production runs with `autoAsk: true` and the `ConfirmationSlip` view is defined but never presented
  - Several bundled fonts are flagged personal-use/demo-only (`isFreeLicense=false` in `PageStyle.swift`)

## Tech stack

| Layer    | Tech                                      |
| -------- | ----------------------------------------- |
| iPad app | Swift, SwiftUI, PencilKit (XcodeGen `project.yml`) |
| Backend  | TypeScript, Fastify 4, Zod, Pino          |
| AI       | OpenRouter REST (gated by `OPENROUTER_API_KEY`); deterministic mock default |
| Tests    | Swift Testing (`iPadApp/Tests`), `node --test` (Backend) |

## How to run

Backend commands were tested on this machine (Node v24; Swift cannot be
compiled here — iPad steps follow the project's own docs):

```bash
cd Backend
npm install
npm run build        # tsc → dist/
npm run typecheck    # tsc --noEmit
# npm test           # currently broken on Node 24 (ts-node loader incompatibility)
```

To run the server (needs env): create `.env` with `DEVICE_AUTH_TOKEN`, then
`npm start`. In mock mode no API key is needed.

iPad app (on a Mac with Xcode — not verifiable here):

```bash
cd iPadApp
xcodegen generate    # then open the .xcodeproj and build/run on iPad simulator
```

## Screenshots

No screenshots ship with the repo. The banner at the top of this README is
the visual summary.

## What you can add more

- [ ] Rewire the orphaned vector-ink engine into answer rendering — or delete it; the README claims answers render as "genuine vector ink" but they currently render as font text
- [ ] Fix the iPad test suite so it compiles against the current `PageViewModel` init (stale `styleSettings`/`profileStore`/`animator` args, missing `ScrollSyncCoordinator`)
- [ ] Fix or replace the backend test runner (ts-node `--loader` is deprecated and crashes on Node 24) so `npm test` actually runs
- [ ] Reconcile the docs: `Backend/README.md` describes a Kiro CLI provider that isn't in the code — update docs or re-add the provider
- [ ] Decide on `autoAsk: true` in production and either wire up `ConfirmationSlip` or remove it
- [ ] Resolve font licensing: several bundled fonts are personal-use/demo-only — gate or replace before any distribution
- [ ] Run the physical-device checklist (`docs/PHYSICAL_DEVICE_CHECKLIST.md`) — nothing device-specific has been validated
- [ ] Add a CI workflow running backend build/typecheck on push (no `.github/workflows` yet)

## Project structure

```
├── Backend/
│   ├── src/
│   │   ├── server.ts / app.ts / config.ts   # Fastify app, zod env validation
│   │   ├── schema.ts / text.ts              # /v1/answers wire models
│   │   └── providers/                       # MockAnswerProvider, OpenRouterAnswerProvider, factory
│   └── test/                                # http / provider / redaction / unit tests
├── iPadApp/
│   ├── project.yml                          # XcodeGen project
│   └── Sources/
│       ├── App/                             # LivingPageApp, AppEnvironment (wires view model, autoAsk:true)
│       ├── Model/                           # PageViewModel (phase machine)
│       ├── UI/                              # PageView, InkCanvasView, CalibrationView, PaperView…
│       ├── Ink/                             # vector-ink engine (currently orphaned)
│       ├── Recognition/                     # on-device handwriting recognition
│       ├── Calibration/                     # personal handwriting profile
│       ├── Networking/                      # HTTPAnswerClient, wire models
│       └── Fonts/                           # 10 bundled handwriting fonts
├── DESIGN.md / PRODUCT.md                   # product design + IP rules (no Harry Potter branding)
├── fonts/                                   # (repo-level font assets)
├── docs/PHYSICAL_DEVICE_CHECKLIST.md        # device validation checklist
└── banner.webp                              # this README's banner
```

---
*README written after code audit on 2026-10-08.*
