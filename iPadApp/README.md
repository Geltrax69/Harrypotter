# Living Page — iPad app

SwiftUI + PencilKit iPad app. You handwrite one question with Apple Pencil,
confirm the on-device recognition, and a concise answer writes itself below as
genuine display-only vector ink in a preset hand or your calibrated personal style.

> Status: builds and unit-tests pass on the **iOS 27 Simulator**. Physical-device
> behavior is **not claimed as validated** — see the checklist at the end and
> `../docs/PHYSICAL_DEVICE_CHECKLIST.md`.

## Project generation (XcodeGen)

`project.yml` is the source of truth; the `.xcodeproj` is generated and is
**git-ignored** at the repo root. Regenerate after any `project.yml` change:

```bash
brew install xcodegen        # once
cd iPadApp
xcodegen generate
open LivingPage.xcodeproj
```

The generated project targets **iPadOS 27**, iPad-only (`TARGETED_DEVICE_FAMILY=2`),
Swift 6 with complete strict concurrency. XcodeGen merges the
`targets.LivingPage.info.properties` block into `Sources/Info.plist`, including
the App Transport Security settings below.

## App Transport Security

`Sources/Info.plist` (and `project.yml`) declare:

- `NSLocalNetworkUsageDescription` — user-facing reason for local network access.
- `NSAppTransportSecurity.NSAllowsLocalNetworking = true` — permits direct
  connections to local hosts (local HTTPS and mDNS `.local`) for development.

This does **not** enable arbitrary internet cleartext: `NSAllowsArbitraryLoads`
is deliberately absent. On a physical device the backend must be reached over
**HTTPS** (see below).

## Simulator demo flags (launch arguments)

The UI-testing / demo path substitutes deterministic dependencies so the flow
runs without an Apple Pencil:

| Launch argument   | Effect                                                                 |
|-------------------|------------------------------------------------------------------------|
| `--ui-testing`    | Uses `DeterministicRecognizer` + `DeterministicAnswerClient`, in-memory profile/key-value stores. Never touches the network, real Keychain, or Application Support. |
| `--seed-profile`  | Pre-seeds a synthetic usable Personal profile so Personal-hand paths can be exercised. |

## Real app launch environment

For a real (non-UI-testing) run against a backend, set these under
**Product → Scheme → Edit Scheme… → Run → Environment Variables**. No real
secrets are committed.

| Variable                              | Purpose                                                                 |
|---------------------------------------|-------------------------------------------------------------------------|
| `LIVINGPAGE_BASE_URL`                 | Backend origin. **HTTPS accepted anywhere; cleartext HTTP accepted only for `localhost`/`127.0.0.1`/`::1`.** Malformed, remote-cleartext, non-`http(s)`, or credential-bearing URLs are rejected and safely fall back to `http://localhost:8080` (no typing UI is shown). |
| `LIVINGPAGE_BOOTSTRAP_TOKEN`          | One-time device bearer token persisted to the Keychain. Must be **≥ 16 characters** (matches the backend's `DEVICE_AUTH_TOKEN` minimum). Must equal the backend `DEVICE_AUTH_TOKEN`. |
| `LIVINGPAGE_RESET_DEVICE_CREDENTIAL`  | `1` = one-shot credential rotation (see below).                         |

The token is stored in the Keychain
(`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) and is **never logged,
printed, or displayed** in UI.

## One-shot credential rotation

Credential handling (`AppEnvironment.bootstrapCredentialIfNeeded`):

- **Ordinary launch:** if a credential already exists in the Keychain it is
  **never overwritten**. A `LIVINGPAGE_BOOTSTRAP_TOKEN` is only consumed when the
  Keychain is empty, and only if it is ≥ 16 characters.
- **Explicit rotation/reset:** launch **once** with
  `LIVINGPAGE_RESET_DEVICE_CREDENTIAL=1` (plus a new
  `LIVINGPAGE_BOOTSTRAP_TOKEN`). The existing credential is cleared, then the new
  token is bootstrapped. Remove the env var after that single launch so it does
  not clear again.
- A reset with **no** new token clears the credential and leaves the device
  unconfigured (reported as `clearedWithoutNewToken`).
- A short token (< 16 chars) is rejected and not saved.

Outcomes are returned as a typed enum (`saved`, `preservedExisting`, `noToken`,
`tokenTooShort`, `saveFailed`, `clearedWithoutNewToken`) — never the token value.

## HTTPS requirement on a physical iPad

On the **Simulator**, `http://localhost:8080` works (loopback cleartext is
permitted). On a **physical iPad**, the backend must be reached over **HTTPS**
(e.g. behind a local TLS reverse proxy). A remote `http://` URL is rejected by
`AppEnvironment.resolveBaseURL` and falls back to localhost, which is unreachable
from a device — so provide an `https://` origin.

## Calibration workflow & personal profile

- **Workflow:** a resumable calibration flow (`CalibrationPlan`,
  `CalibrationSampleProcessor`) captures glyph banks and rhythm-phrase metrics
  from your Apple Pencil samples. Progress is saved so calibration can be paused
  and resumed.
- **Profile location:** `Application Support/Handwriting/profile.json`
  (progress in `progress.json`), via `FileHandwritingProfileStore`.
- **Protection:** atomic writes with
  `FileProtectionType.completeUntilFirstUserAuthentication`, excluded from
  iCloud/iTunes backup. On a **physical device** a protected-write failure
  surfaces as `ProfileStoreError.protectedWriteUnavailable` rather than silently
  downgrading to an unprotected file. The Simulator (or an injected test
  directory) may fall back to an atomic unprotected write since it lacks real
  data-protection guarantees.
- **Delete behavior:** deleting the personal handwriting removes both
  `profile.json` and `progress.json` and clears the "has profile" flags. If
  Personal was the selected style, the app remains usable by falling back to a
  preset hand.

## Style selection & fallback behavior

- Selected style is persisted via `StyleSettings` (`UserDefaults` in production,
  in-memory in tests). Default is `.uprightOpen`.
- `HandResolver` resolves the active glyph provider:
  - Presets (`uprightOpen`, `quickSlanted`, `compactRounded`) render directly.
  - `personal` renders with `PersonalHand` **only when a usable profile exists**
    (≥ ~half the lowercase alphabet has renderable ink); missing glyphs fall back
    to the preset.
  - If Personal is selected but no usable profile exists, the resolver returns
    the fallback preset and flags `needsCalibration` so the UI can prompt to
    finish calibration. Unsupported glyphs fall back to a legible preset rather
    than disappearing.

## Accessibility

- VoiceOver exposes the recognized question, the answer, status, and controls
  even though the visible answer is ink.
- Reduce Motion replaces per-stroke animation with a line-level or immediate
  reveal.
- Native control semantics, sufficient contrast, adaptable text sizing, and
  large iPad-appropriate hit targets.

## Test commands

```bash
cd iPadApp
xcodegen generate

# Unit tests (pick an available iOS 27 iPad simulator)
xcodebuild test -project LivingPage.xcodeproj -scheme LivingPage \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
  -only-testing:LivingPageTests

# UI tests (optional; slower)
xcodebuild test -project LivingPage.xcodeproj -scheme LivingPage \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
  -only-testing:LivingPageUITests
```

## Physical device checklist (not yet validated)

The following require real hardware and are tracked in
`../docs/PHYSICAL_DEVICE_CHECKLIST.md`; this app does **not** claim them as
validated:

- Pencil-only question input; finger gestures scroll/navigate only.
- Idle-pause recognition (~1.5s), cancel, and stale-recognition handling.
- Handwriting recognition error-rate targets.
- Real Apple Pencil force/tilt capture and per-stroke render state.
- File-protection and Keychain behavior on device.
- Live network, retry, and offline recovery against an HTTPS backend.
- Long-answer rendering performance.
- Dark mode, VoiceOver, Reduce Motion, and rotation on device.
