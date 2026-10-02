# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Stack

delegated: Native SwiftUI/UIKit with PencilKit for the iPad app, plus a Node.js TypeScript service that brokers Kiro CLI headless requests. XcodeGen defines the local Xcode project without committing generated project drift.

## Users

The initial user is the owner of the app, using a compatible iPad and Apple Pencil as a personal prototype. They want to ask spontaneous questions in handwriting without switching to a keyboard or conventional chat interface.

## Product Purpose

Living Page is a single-page, Apple Pencil-first question-and-answer notebook. The user handwrites one question, confirms its on-device recognition, and receives a concise Kiro-generated response that writes itself below the question as vector ink. Success is a complete question-to-answer interaction with no typing and a clear reset back to an empty page.

## Positioning

The answer is not displayed as ordinary UI text or a handwriting font: Living Page composes and reveals editable vector strokes using a preset hand or a profile derived from the user's own Apple Pencil samples. Raw handwriting and the personal style profile remain on the device.

## Operating Context

The primary workflow is a quiet, full-screen iPad page used with Apple Pencil. Pencil input creates marks; finger gestures navigate the page. Recognition starts after an idle pause, then an inline confirmation step precedes any network request. The page preserves the question through recoverable failures and clears only on explicit user action.

## Capabilities and Constraints

- One question and one answer at a time; clearing starts a new page.
- Apple Pencil-only question input; no keyboard entry path in the main experience.
- On-device handwriting recognition using iPadOS 27 PencilKit APIs.
- English/Latin responses with an initial maximum of approximately 120 words.
- Several original preset vector hands plus a resumable personal handwriting calibration flow.
- Personal profiles preserve normalized stroke geometry, order, timing, force, tilt, and spacing locally with iOS file protection.
- Only confirmed recognized text, locale, a request identifier, and answer-length limit may cross the network.
- A secure TypeScript backend invokes Kiro CLI headless mode. `KIRO_API_KEY` is server-only and supplied later through an untracked environment file or hosted secret.
- Kiro access requires an eligible account and remains environment-gated until credentials are supplied.
- Hosting is deliberately undecided; no cloud infrastructure is created without explicit approval.
- Personalized output is a recognizable creative approximation, not forensic reproduction. Signatures are never collected or generated, and generated handwriting cannot be exported in this prototype.

## Brand Commitments

The product name is **Living Page**. The experience must be original and must not reproduce Harry Potter names, crests, fonts, sounds, parchment treatments, or other protected material. Its sense of magic comes from authentic ink behavior and restrained interaction rather than franchise imagery or novelty effects.

## Evidence on Hand

No logo, illustration, font, handwriting dataset, production endpoint, customer evidence, or real Kiro credential has been supplied. Future work must not fabricate commercial claims or imply production availability. Test fixtures and demonstration handwriting are synthetic or recorded locally for the prototype.

## Product Principles

1. Pencil first: asking and answering should feel continuous with handwriting, never like a disguised chat form.
2. Private by construction: recognize locally, keep stroke data local, and transmit the minimum confirmed text.
3. Ink is the interface: vector stroke quality, timing, and legibility matter more than decorative magic.
4. Recover without loss: recognition, connectivity, and provider failures preserve the user's question and offer a clear next action.
5. Honest personalization: celebrate a user's writing traits while disallowing signatures, export, or claims of exact identity replication.

## Accessibility & Inclusion

VoiceOver must expose the recognized question, answer, status, and controls even though the visible response is ink. Reduce Motion replaces per-stroke animation with line-level or immediate reveal. Controls use native semantics, sufficient contrast, adaptable text sizing, and large iPad-appropriate hit targets. Unsupported personal glyphs fall back to a legible preset rather than disappearing.
