---
name: Living Page
description: A single Apple Pencil sheet you write a question onto and watch answer itself in ink.
colors:
  sheet-light: "#f4f5f7"
  sheet-dark: "#16181b"
  sheet-edge-light: "#e6e8ec"
  sheet-edge-dark: "#212327"
  graphite-light: "#292c32"
  graphite-dark: "#e0e2e6"
  graphite-soft-light: "#636872"
  graphite-soft-dark: "#9ca0a8"
  indigo-light: "#353c73"
  indigo-dark: "#8a92d4"
typography:
  status:
    fontFamily: "SF Pro (system), .subheadline"
    fontWeight: 500
  confirmation-title:
    fontFamily: "SF Pro (system), .title3"
    fontWeight: 400
  recovery-headline:
    fontFamily: "SF Pro (system), .headline"
    fontWeight: 400
  control-label:
    fontFamily: "SF Pro (system), .body / .caption"
    fontWeight: 400
  answer-ink:
    fontFamily: "Vector PKStroke alphabet (not a font)"
rounded:
  slip: "18pt"
  pad: "14pt"
  control: "capsule"
spacing:
  outer: "24pt"
  slip-padding: "20pt"
  action-gap-h: "12pt"
  action-gap-v: "8pt"
  rule-rhythm: "44pt"
  margin-x: "56pt"
components:
  button-ask-kiro:
    backgroundColor: "{colors.indigo-light}"
    textColor: "{colors.sheet-light}"
    rounded: "{rounded.control}"
    height: "44pt"
  button-keep-writing:
    textColor: "{colors.graphite-light}"
    rounded: "{rounded.control}"
    height: "44pt"
  button-start-over:
    rounded: "{rounded.control}"
    height: "44pt"
  tool-button:
    textColor: "{colors.graphite-light}"
    rounded: "{rounded.control}"
    width: "44pt"
    height: "44pt"
  tool-button-selected:
    textColor: "{colors.indigo-light}"
    rounded: "{rounded.control}"
    width: "44pt"
    height: "44pt"
  confirmation-slip:
    backgroundColor: "{colors.sheet-edge-light}"
    rounded: "{rounded.slip}"
    padding: "20pt"
  recovery-slip:
    backgroundColor: "{colors.sheet-edge-light}"
    rounded: "{rounded.slip}"
    padding: "20pt"
---

# Design System: Living Page

## Overview

**Creative North Star: "Living Graphite Folio"**

Living Page is one quiet sheet of cool mineral paper you write a question onto by hand and watch answer itself. It refuses the chat category default outright: there is no message list, no card grid, no typing field, no send box. The page IS both the input and the output. Graphite ink carries everything the hand makes; deep indigo is reserved for the system's voice — the status line and the answer, which is written as real vector ink in the same synchronized page plane as the question rather than set as UI text. Native SF typography and SF Symbols do the plumbing so the interface itself stays silent and the ink is the only thing that speaks.

The system is restrained to the point of near-invisibility at rest. On launch the whole sheet is the surface: a faint ruled body with a left-margin rule, a single quiet status line ("Write a question."), the style picker, and the bottom-trailing pen/eraser/clear controls. Nothing else competes; there is no onboarding card, no modal, no keyboard. Controls are quiet, standard, HIG-native, and physically large enough for a hand holding a Pencil. The magic is meant to come entirely from authentic ink behavior — real strokes revealing themselves in indigo below the question — not from ornament, glow, or novelty effects.

Depth is expressed by tonal layering of native materials rather than by shadow craft: the sheet, a slightly recessed sheet edge, and quiet indigo/graphite rules stack to read as one continuous piece of paper. Both light and dark are first-class; every color is authored as a light/dark pair so the folio reads as the same sheet under either appearance.

**Key Characteristics:**
- One sheet: the page is simultaneously the question input and the answer output.
- Graphite for the hand, deep indigo for the system's single voice.
- The answer is real vector ink (PKStroke), never a font or Text.
- Quiet native/HIG controls with 44pt hit targets; nothing competes with the ink.
- Light and dark authored as equal pairs; flat tonal paper, no parchment, no franchise imagery.

## Colors

A cool, low-chroma mineral palette: near-neutral paper, a graphite family for the hand and text, and a single deep-indigo accent reserved for the system voice. Each role is authored as an explicit light/dark pair; the frontmatter carries both members of each pair as separate tokens.

### Primary
- **Deep Indigo** (light `#353c73` / dark `#8a92d4`): The system's one voice. Used for the answer ink, the error/status accent, the prominent "Ask Kiro" / "Try Again" action, the selected tool tint, calibration progress and save action, and the faint left-margin and baseline rules. Never used for hand input.

### Neutral
- **Cool Mineral Paper — Sheet** (light `#f4f5f7` / dark `#16181b`): The writing surface itself; fills the whole page behind all ink.
- **Sheet Edge** (light `#e6e8ec` / dark `#212327`): A slightly recessed tonal layer for the confirmation/recovery slips, the tool-control capsule, and the calibration pad. Conveys depth without shadow.
- **Graphite** (light `#292c32` / dark `#e0e2e6`): The ink the hand writes with and the primary text color; also the default (unselected) tool tint and neutral action tint.
- **Graphite Soft** (light `#636872` / dark `#9ca0a8`): Secondary labels — the status line, supporting captions, the "I read…" lead-in, and the faint horizontal body rules.

Indigo also has a translucent companion (`indigoSoft`, indigo at 10% light / 16% dark) reserved for the faintest indigo washes.

### Named Rules
**The One-Voice Indigo Rule.** Deep indigo belongs to the system alone. It appears only where the app is speaking — the answer ink, the status/error line, the primary confirm/retry action, calibration progress and rules. The hand never writes in indigo; graphite is the human, indigo is the page answering back. Its rarity is what makes the answer feel alive.

## Typography

**Control Font:** SF Pro (the iOS system font), via semantic text styles.
**Answer "Font":** none — the visible answer is a vector PKStroke alphabet, not type.

**Character:** System SF typography is deliberately quiet and utilitarian; it serves labels, status, and controls without drawing attention. The authored, personal handwriting is the only expressive letterform in the product, and it is rendered as real ink rather than a typeface.

### Hierarchy
- **Recovery Headline** (`.headline`, regular weight): the error message on the recovery slip, tinted indigo.
- **Confirmation Title** (`.title3`, regular weight): the recognized question read back inside quotation marks, in graphite.
- **Status** (`.subheadline`, medium weight): the single top-bar status line; graphite-soft normally, indigo on error.
- **Control Label** (`.body` / `.caption`, regular weight): button labels, style-picker label, calibration prompts and captions.
- **Answer Ink** (vector strokes, ~3pt): the answer, composed from a preset or personal hand and drawn in indigo. Not part of the type scale — it is ink.

### Named Rules
**The Ink-Not-Type Rule.** The answer is never a font, Text, raster image, or glyph outline. It is the exact PKDrawing produced by the ink compositor, revealed as real vector strokes in the same synchronized page plane as the question. System type is allowed only for controls, status, and labels — never for the answer itself.

## Layout

The app is a single full-bleed sheet, not a scaffold of panels. `Palette.sheet` ignores safe areas and fills the screen; content is arranged directly on it.

- **Outer insets:** 24pt horizontal is the standard page inset for the top bar, the inline slips, and the bottom-trailing control cluster. The top bar adds 12pt top padding.
- **Paper rhythm:** the body rules repeat every 44pt baseline-to-baseline, with a single left-margin rule at 56pt. The rules are drawn behind all ink, are non-interactive, and are hidden from assistive technology. (The calibration pad uses its own tighter guide set at a fixed 200pt height.)
- **Control placement:** primary tools sit bottom-trailing (pen, eraser, clear); the status line and style picker sit in the top bar (leading and trailing respectively).
- **Single scrollable surface:** the question canvas is the sole scrollable page surface. It publishes its scroll offset to a shared coordinator, and the answer canvas — which has its own scrolling disabled — mirrors that exact offset so the answer stays pinned in the same absolute page coordinate space directly below the question while the page is panned. Both canvases size their scrollable content to fit question plus a long revealed answer (with a comfortable ~240pt trailing margin).
- **Adaptation:** the slips' action rows and the calibration controls use `ViewThatFits(in: .horizontal)` to try a horizontal row of actions first and fall back to a vertical stack when labels grow too wide (large Dynamic Type or narrow width). 44pt hit targets are preserved in both layouts. This is the app's core adaptive behavior; there are no pixel breakpoints.

## Elevation & Depth

The system uses no drop shadows. Depth is conveyed entirely by tonal layering of native materials: the sheet, the slightly recessed sheet-edge fill for slips and the control capsule, and faint low-opacity rules. Surfaces read as physically stacked paper, not as floating cards.

### Named Rules
**The Flat-Paper Rule.** Surfaces are flat. Never add drop shadows, glows, or bevels to lift an element. Separation comes from the sheet-edge tonal fill and hairline rules, so the whole app continues to read as one continuous sheet under both light and dark.

## Shapes

The form language is soft-cornered rectangles and native capsules, all continuous-curvature where SwiftUI allows it.

- **Slips** (confirmation, recovery): 18pt continuous rounded rectangles filled with the sheet-edge tone.
- **Calibration pad:** a 14pt continuous rounded rectangle with a hairline graphite-soft border.
- **Controls:** native capsule-shaped bordered buttons; the tool cluster sits inside a `Capsule` filled with the sheet-edge tone.
- **Rules:** 1pt hairlines only — horizontal body rules in graphite-soft at ~14% opacity, the left margin in indigo at ~16% opacity.

## Components

### Buttons
- **Shape:** native `.bordered` / `.borderedProminent` capsules; every button reserves a 44pt minimum hit target.
- **Ask Kiro / Try Again (primary):** `.borderedProminent` tinted deep indigo — the system-voice action. Leading SF Symbol (`arrow.up.circle.fill` / `arrow.clockwise`).
- **Keep Writing (neutral):** `.bordered` tinted graphite, `pencil.line` symbol.
- **Start Over (destructive):** `.bordered` with destructive role (system red), `arrow.counterclockwise` symbol.
- **Layout:** actions live in a ViewThatFits horizontal-row-then-vertical-stack; horizontal gap 12pt, vertical gap 8pt.

### Tool Controls
- **Style:** three `.bordered` buttons (pen, eraser, clear) each 44×44pt, grouped inside a sheet-edge `Capsule` with 6pt inset padding, pinned bottom-trailing at 24pt insets.
- **State:** the active tool tints indigo and carries the `.isSelected` accessibility trait; inactive tools tint graphite. Clear tints graphite and confirms via a native dialog when the page is non-blank.

### Confirmation Slip (signature)
Rises inline from where the writing is, ~96pt above the bottom. Reads the recognized text back as "I read…" (graphite-soft lead-in) followed by the quoted question in `.title3` graphite — deliberately with no editable text field, since recognized text is not keyboard-editable. Offers Ask Kiro / Keep Writing / Start Over. Filled sheet-edge tone, 18pt corners, 20pt padding. Enters with a bottom-move+opacity transition, or a plain opacity fade under Reduce Motion.

### Recovery Slip (signature)
Same shell and adaptation as the confirmation slip. Shows the error message as an indigo `.headline` with an `exclamationmark.circle`, preserves and re-displays the recognized text so nothing feels lost, and adapts its actions to the failure: a "Try Again" primary appears only when retrying is sensible (retryable network errors), always alongside Keep Writing and Start Over.

### Style Picker
A borderless native `Menu` labeled with the current hand and a `textformat.alt` symbol, 44pt min height. Lists the three preset hands — **Upright**, **Slanted**, **Rounded** — with a checkmark on the selection, then Personal. Personal shows "Finish calibration" when no usable profile exists, or the selectable Personal hand plus "Refine calibration" when one does. A destructive "Delete my handwriting" appears whenever a personal profile exists on the device.

### Calibration Surface (signature)
A native sheet on the same mineral paper: privacy copy stating this is not a signature, section + overall indigo progress bars, a prompt card, a Pencil-only capture pad over ruled guide paper, a live vector-ink preview of the last saved character ("Your ink"), and a ViewThatFits control row (Clear, Previous, Save Sample [indigo primary], Next/Done). The preview and answer prove the personalization is real ink, never a font.

### Answer Ink (signature)
The defining component. A display-only, non-interactive canvas layered above the question in the same page. It renders the exact vector PKDrawing from the compositor — never a font, Text, raster, or outline — in deep indigo (`#353c73`), ~3pt. Strokes reveal progressively in true drawing order. An invisible semantic label carries the answer text to VoiceOver.

The three preset hands are distinguished by their metric signatures, expressed most legibly at their characteristic letterform: **Upright** (tall, vertical, generous — em height 40, near-zero slant), **Slanted** (fast rightward slant — em height 38, slant 0.22, tighter tracking), and **Rounded** (small, dense, corner-softened — em height 34, slant 0.05). Unsupported glyphs fall back to a legible preset rather than disappearing.

## Do's and Don'ts

### Do:
- **Do** keep deep indigo for the system's voice only — answer ink, status/error, the primary confirm/retry action (the One-Voice Indigo Rule).
- **Do** render every answer and personalized preview as real vector PKStroke ink, never as a font or Text (the Ink-Not-Type Rule).
- **Do** hold surfaces flat and build depth from the sheet-edge tonal fill and hairline rules only (the Flat-Paper Rule).
- **Do** preserve 44pt hit targets and use ViewThatFits (horizontal row → vertical stack) so slips and calibration controls adapt to width and large Dynamic Type.
- **Do** use 24pt outer insets, 18pt slip corners, and the 44pt body-rule rhythm as the durable spatial constants.
- **Do** author every color as a light/dark pair so the folio is equally first-class in dark mode.
- **Do** honor Reduce Motion by swapping the per-stroke reveal for line-level or immediate reveal and replacing slip move transitions with a plain opacity fade.
- **Do** keep the answer pinned in the question's absolute coordinate space by mirroring the single scrollable surface's offset.

### Don't:
- **Don't** introduce a message list, card grid, typing field, send box, or any chat-bubble metaphor — the single sheet is both input and output.
- **Don't** add parchment textures, glows, ornament, or any Harry Potter / franchise imagery, fonts, crests, or sounds (the no-franchise / no-parchment guardrail).
- **Don't** let the hand write in indigo or let the system speak in graphite; the two voices never swap.
- **Don't** set the answer as a handwriting font, styled Text, or raster image.
- **Don't** add drop shadows, bevels, or lift effects to separate surfaces.
- **Don't** promote a single surface's composition into a global rule; only the durable single-sheet principles above are system-wide.
