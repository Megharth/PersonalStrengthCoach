---
target: PersonalStrengthCoach/WorkoutLoggerView.swift
total_score: 31
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 3
timestamp: 2026-08-18T01-22-24Z
slug: personalstrengthcoach-workoutloggerview-swift
---
## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|---|---:|---|
| 1 | Visibility of System Status | 4 | Active session bar clearly exposes rest, elapsed time, and volume; save and draft failures are surfaced. |
| 2 | Match System / Real World | 4 | Native workout language and familiar set-entry controls fit the gym context. |
| 3 | User Control and Freedom | 3 | Cancel, discard confirmation, swipe deletion, and undo are strong; there is no explicit way to cancel an active rest timer. |
| 4 | Consistency and Standards | 3 | Native List, sheets, dialogs, and toolbar actions are consistent; set details are less discoverable than the primary fields. |
| 5 | Error Prevention | 3 | Destructive actions are guarded and weights are clamped, but reps accept zero/negative values and Save remains enabled for invalid/incomplete input. |
| 6 | Recognition Rather Than Recall | 3 | Previous performance and last-trained context reduce recall; set type and RPE require opening per-set details. |
| 7 | Flexibility and Efficiency of Use | 3 | Routines, prefills, draft recovery, and add-set defaults accelerate repeat users; sequential entry still requires repeated field taps. |
| 8 | Aesthetic and Minimalist Design | 3 | Progressive disclosure keeps the dense logger calm; tertiary previous-performance text is too visually faint. |
| 9 | Help Users Recognize, Diagnose, and Recover from Errors | 3 | Alerts preserve the form and give next steps; inline RPE state is not announced robustly to VoiceOver. |
| 10 | Help and Documentation | 2 | The surface is learnable but has no contextual explanation for RPE, set types, or the meaning of previous-performance cues. |
| **Total** | | **31/40** | **Good foundation; address weak input validation and accessibility before release.** |

## Design Specificity Verdict

**LLM assessment:** The logger feels authored for Personal Strength Coach rather than category-interchangeable. The combination of a calm native List, a mint completion signal, historical set prefills, last-trained context, and an active-workout status inset expresses the product's “Recovery Compass” promise without turning the logger into a decorative dashboard. The main opportunity is to make the product's progression intelligence more legible without increasing the number of simultaneous decisions.

**Deterministic scan:** `detect.mjs --json PersonalStrengthCoach/WorkoutLoggerView.swift` returned `[]`. This detector targets web markup/styles/scripts, so it has no applicable rules for native SwiftUI source; there are no detector findings or false positives. Browser visualization was not applicable: this target is an iOS source file, not a browser-viewable surface, and no overlay was created.

## Overall Impression

This is a credible, ship-shaped workout-entry surface: the primary loop is obvious, recovery context is always nearby, and the implementation respects iOS conventions. The single biggest opportunity is to turn “fast and forgiving” into “fast and unmistakably safe” by validating reps at the field, strengthening the low-contrast history cue, and giving assistive technologies equivalent feedback for invalid state and deletion recovery.

## What's Working

- **Primary task hierarchy:** weight, reps, and completion stay in the first row while RPE and set type move behind a clearly labeled disclosure (lines 717–801). That is the right density tradeoff for real gym use.
- **Resilience under interruption:** resumable drafts, scene-phase persistence, save-error preservation, and one-tap set undo (lines 512–605, 421–430, 491–509) protect the user's work instead of forcing them to reconstruct it.
- **Native, product-specific status:** the safe-area bar (lines 437–476) turns rest, elapsed time, and volume into a quiet training instrument, and its combined accessibility label is unusually thoughtful (lines 478–487).

## Priority Issues

### [P1] Validate repetitions at the point of entry

**What:** `NumericFieldInt` accepts any formatted integer and the save path only filters by completion; unlike weight, reps have no lower bound or inline validation (lines 733–737, 852–872, 625–634).

**Why it matters:** A lifter can record 0 or negative repetitions, then receive a workout that appears valid but undermines volume, estimated 1RM, and progress history. This is a data-integrity and trust problem, not merely polish.

**Fix:** Enforce a minimum of 1 for reps in the binding/model boundary, show an inline “Reps must be at least 1” state, and prevent completion/save until the row is corrected. Keep the entered form intact. Suggested command: `/impeccable harden`.

### [P1] Restore readable contrast for previous performance

**What:** Historical guidance is rendered as `.caption2` with `.tertiary` foreground (lines 803–809), and stale values are dimmed further through opacity (lines 703–705).

**Why it matters:** The most valuable progression cue can disappear in dark mode, larger text, or low vision—especially when the user is deciding what to load for the next set. It conflicts with the product's promise to make real history legible.

**Fix:** Use `.caption` or `.subheadline` with `.secondary` for the default previous cue; reserve tertiary/dimming for explicitly stale metadata, and ensure the cue remains distinguishable from decorative metadata. Suggested command: `/impeccable typeset`.

### [P1] Make invalid and destructive states equivalent for VoiceOver

**What:** RPE invalidity is communicated through a red border and adjacent text (lines 781–789), while the deletion recovery overlay relies on nested children without a concise announcement (lines 491–509).

**Why it matters:** Sighted users get immediate correction and recovery affordances; VoiceOver users may not learn that a value is invalid or that Undo is available. Color and proximity alone are insufficient state communication.

**Fix:** Add an accessibility value/hint that includes the invalid RPE state and correction, and give the recovery overlay a concise label such as “Set deleted. Undo available.” Ensure focus/order lands predictably on Undo after deletion. Suggested command: `/impeccable audit`.

### [P2] Reduce repeated taps during sequential set entry

**What:** Adding a set appends a row but does not move focus to its weight field (lines 820–824); each set requires separate taps to focus weight and reps.

**Why it matters:** This is the dominant repeated interaction for a power user logging several sets. The surface is resilient but not yet frictionless in the thumb-and-keyboard flow.

**Fix:** Track the newly added set ID and focus its weight field, then allow the user to advance to reps and completion without leaving the keyboard. Preserve a clear Done escape. Suggested command: `/impeccable optimize`.

### [P2] Clarify the active-rest lifecycle

**What:** Completing any set starts or resets the global rest timer (lines 738–741, 607–611), but the status bar offers no visible cancel/skip action and remains active even if the exercise is removed.

**Why it matters:** The timer can become semantically stale, and users cannot quickly express “I am ready” or “skip rest.” That weakens trust in the status instrument during real training.

**Fix:** Add a compact native action to end/skip rest and clear the timer when the related context is no longer meaningful; keep it secondary to the countdown. Suggested command: `/impeccable clarify`.

## Persona Red Flags

**Alex (Impatient Power User):** Routine prefills and previous-set defaults are good accelerators, but Add set does not advance focus, so multi-set entry repeatedly interrupts the keyboard flow. RPE/set type are efficient once learned but hidden behind a disclosure with no shortcut.

**Jordan (Confused First-Timer):** “RPE,” “set type,” “volume,” and “last trained” assume training vocabulary. The surface explains none of them contextually; the first-timer can complete the main row, but may skip or misunderstand the optional details.

**Sam (Accessibility-Dependent User):** Most controls have strong labels and 44-point targets, but the `.tertiary`/`.caption2` history cue may be too faint, and RPE invalidity plus the deletion Undo state are not guaranteed to be announced as state changes.

## Cognitive Load Assessment

**Failed checklist items: 2/8 (moderate-low load).**

- **Visual hierarchy:** mostly passes, but the faint previous-performance cue underweights a key decision aid.
- **Progressive disclosure:** passes for RPE and set type.
- **Minimal choices:** passes in the main row; the expanded details expose only two related decisions.
- **Single focus / chunking / grouping / one thing at a time / working memory:** pass. The set row groups the immediate logging task, and the status bar keeps rest context local rather than requiring recall.

The surface has one potentially overloaded moment: a set row can combine two fields, completion, disclosure, previous performance, and swipe deletion. The current hierarchy keeps it manageable, but larger Dynamic Type should be checked on-device.

## Emotional Journey

The opening is reassuring: a clear “Add your first exercise” state and routine entry reduce the fear of a blank workout. During the workout, the status bar gives a quiet sense of progress and the mint completion state creates a small positive cadence. The most important recovery moment is after an accidental swipe; Undo is immediate and non-blocking. The emotional valley is a failed save or invalid RPE: the form is preserved, which is right, but the user must rely on an alert and hunt through expanded rows. Inline, announced correction would make the recovery feel more controlled.

## Minor Observations

- The Save toolbar action is always enabled, so users can invoke avoidable validation work repeatedly.
- The computed previous-performance dictionary performs a most-recent lookup per distinct exercise on every render; current workout sizes make this acceptable, but caching would be a sensible later optimization.
- `EditableSet` equality compares all mutable fields in addition to its UUID; this is safe but more work than identity-based equality requires.
- The native detector cannot evaluate Dynamic Type, Dark Mode, VoiceOver focus order, or simulator posture; those remain device-level verification items.

## Questions to Consider

- Is RPE intended as an expert-only field, or should the first expansion explain it in one short phrase (“effort from 0–10”)?
- Should the product's signature historical cue be visually stronger than the current implementation, even if that adds one line of height to every set?
- Is “rest complete” a passive status, or should the logger let the user explicitly skip/cancel rest?
