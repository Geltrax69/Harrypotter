# Living Page — Physical device checklist

Reproducible checks that require a real iPad + Apple Pencil. **None of these are
claimed as validated.** Record evidence for each (see "Recording evidence").

Setup: build to a physical iPad on iPadOS 27, configure the Run scheme with an
**HTTPS** `LIVINGPAGE_BASE_URL` and a ≥ 16-char `LIVINGPAGE_BOOTSTRAP_TOKEN`
matching the backend `DEVICE_AUTH_TOKEN`. The backend must be reachable over
HTTPS (loopback cleartext is Simulator-only).

## 1. Pencil-only input / finger-scroll

- [ ] Writing with Apple Pencil creates ink marks in the question area.
- [ ] A finger does **not** draw; finger drag scrolls/navigates the page.
- [ ] Palm resting while writing does not create stray marks.

## 2. Recognition timing / cancel / stale

- [ ] After ~**1.5 s** idle following a stroke, recognition runs and an inline
      confirmation appears.
- [ ] Adding a new stroke before/after recognition **cancels** the pending or
      stale recognition and re-triggers after the next idle pause.
- [ ] A stale recognition (from earlier ink) is never confirmed for later ink.

## 3. Recognition accuracy (CER) — opt-in evidence

Opt-in character-error-rate spot check on your own handwriting:

- [ ] Preset-target phrases: measured **CER ≤ 5%**.
- [ ] Personal-hand phrases: measured **CER ≤ 10%**.
- [ ] Record sample count, phrases, and computed CER.

## 4. Pencil dynamics & render state

- [ ] Real Apple Pencil **force** and **tilt/azimuth** are captured during
      calibration (values vary with pressure/angle, not constant).
- [ ] Answer ink renders per-stroke with correct order/timing; no dropped or
      duplicated strokes; render state consistent after scroll.

## 5. File protection & Keychain (on device)

- [ ] `profile.json` / `progress.json` write successfully in
      `Application Support/Handwriting/` (a protected-write failure must surface
      as an error, not a silent unprotected downgrade).
- [ ] Device credential persists in the Keychain across app relaunch; ordinary
      relaunch does **not** overwrite it.
- [ ] `LIVINGPAGE_RESET_DEVICE_CREDENTIAL=1` (one launch) rotates the credential;
      removing the flag stops further clearing.
- [ ] Deleting personal handwriting removes both files and the app stays usable
      via preset fallback.

## 6. Network / retry / offline

- [ ] A question over **HTTPS** returns an answer that renders as ink.
- [ ] A remote `http://` base URL is rejected (falls back to localhost) — confirm
      the app does not send cleartext to a remote host.
- [ ] Airplane mode → asking surfaces the offline state and **preserves the
      question**; re-enabling network + retry succeeds.
- [ ] Server 5xx/timeout is retryable and preserves the question.
- [ ] A response whose `requestId`/`locale`/`words` don't match is treated as a
      malformed response (no bogus answer shown).

## 7. Long-answer performance

- [ ] A near-120-word answer renders smoothly (no visible stalls/dropped frames)
      and scrolls in sync with the question.

## 8. Appearance & accessibility

- [ ] **Dark mode:** ink and controls have sufficient contrast.
- [ ] **VoiceOver:** recognized question, answer, status, and controls are all
      announced (even though the answer is ink).
- [ ] **Reduce Motion:** per-stroke animation is replaced by line-level or
      immediate reveal.

## 9. Rotation

- [ ] Portrait ⇄ landscape preserves the question, answer, and scroll position;
      no layout breakage or lost ink.

## Recording evidence

For each check, capture:

- Device model, iPadOS version, Pencil generation, app build/commit.
- Backend commit, provider (`mock`/`kiro`), and base URL scheme (HTTPS).
- Screen recording or screenshots (redact any token — it is never displayed
  anyway).
- For CER checks: the phrases used, sample count, and computed error rate.
- Pass/fail and notes. Store evidence outside the repo; **never commit tokens,
  keys, or real endpoints.**
