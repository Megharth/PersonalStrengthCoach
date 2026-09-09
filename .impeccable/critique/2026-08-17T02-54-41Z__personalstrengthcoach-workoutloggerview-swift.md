---
target: workout logger
total_score: 25
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 2
timestamp: 2026-08-17T02-54-41Z
slug: personalstrengthcoach-workoutloggerview-swift
---
## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|---|---:|---|
| 1 | Visibility of System Status | 3/4 | Rest, elapsed time, volume, completion, draft persistence, and save errors are visible; RPE validity is not. |
| 2 | Match System / Real World | 3/4 | Native workout vocabulary is clear, but “RPE” is unexplained. |
| 3 | User Control and Freedom | 3/4 | Cancel, discard confirmation, exercise confirmation, routine replacement confirmation, and set undo provide good exits; undo is single-slot. |
| 4 | Consistency and Standards | 3/4 | Native patterns and 44pt controls are consistent; duplicate session metrics and the small Undo target are exceptions. |
| 5 | Error Prevention | 2/4 | Destructive actions and draft loss are guarded, but invalid RPE can be entered and silently discarded. |
| 6 | Recognition Rather Than Recall | 3/4 | Per-set previous-performance context and historical prefill are strong; RPE meaning must be recalled. |
| 7 | Flexibility and Efficiency | 2/4 | Routines and copy-forward defaults help; there is no exercise reordering or stronger repeated-entry accelerator. |
| 8 | Aesthetic and Minimalist Design | 3/4 | Calm, native, and focused; top and bottom session summaries duplicate the same information. |
| 9 | Error Recovery | 2/4 | Save failure preserves work and offers retry; invalid RPE has no recovery explanation and Undo is fragile. |
| 10 | Help and Documentation | 1/4 | No contextual explanation for RPE or first-use guidance is available in the logger. |
| **Total** |  | **25/40** | **Acceptable; strong foundation, but address silent data loss and repeated-entry friction before release.** |

## Design Specificity Verdict

**LLM assessment:** Grounded and product-specific, not category-interchangeable. The combination of historical per-set prefill, RPE/set-type domain fields, rest-aware session status, routine starts, mint completion signaling, and interruption-safe drafts clearly belongs to Personal Strength Coach. The use of native `List`, `Section`, `TextField`, `Picker`, and confirmation dialogs is an intentional match for this task-heavy iOS surface, not a lack of authorship.

**Deterministic scan:** The bundled detector completed successfully with exit code 0 and returned `[]`. It is primarily calibrated for web markup and styling, so the empty result is not meaningful proof that SwiftUI has no issues. No actionable browser overlay is available: this is compiled SwiftUI rather than an HTML-renderable target.

## Overall Impression

This is now a credible, quiet workout-entry tool: the common path is materially cleaner because weight, reps, and completion remain visible while RPE and set type move behind progressive disclosure. Historical context and draft recovery do the hard product work. The biggest opportunity is to finish the “fast and trustworthy” promise at the input boundary: prevent invalid RPE from disappearing, provide a reliable keyboard exit, and remove redundant status content.

## What's Working

1. **Previous-performance prefill removes recall burden.** The per-set “Previous” cue and historical defaults let a returning lifter act without switching screens or remembering the last session.
2. **Interruption recovery is unusually strong.** Autosaved drafts, scene-phase persistence, absolute rest deadlines, and preserved form state after save failure fit real gym interruptions.
3. **Destructive actions are graded appropriately.** Frequent set deletion uses lightweight Undo, while exercise removal and routine replacement require explicit confirmation with consequence-specific copy.

## Priority Issues

### [P1] Invalid RPE can disappear silently

**Why it matters:** `RPEEngine.validated` rejects values outside 0–10, but the bound field provides no immediate inline feedback. A user can type an out-of-range value, save, and later discover that it was not retained. That is silent loss of training data.

**Fix:** Validate as the value changes and show “RPE must be between 0 and 10” beside the field, or constrain the entry and block Save while invalid. Preserve the entered form so correction is easy.

**Suggested command:** `/impeccable harden`

### [P1] Numeric keyboards have no reliable Done action

**Why it matters:** `.numberPad` and `.decimalPad` do not provide a Return key. Weight, reps, and RPE are the most repeated interactions in the logger, so the lack of a keyboard toolbar Done control creates cumulative friction and can strand a user mid-entry.

**Fix:** Add a focused-field keyboard toolbar with a clearly labeled Done button, or provide an equivalent native focus-dismiss path without changing the fast-entry layout.

**Suggested command:** `/impeccable harden`

### [P2] Session metrics are duplicated

**Why it matters:** The pinned top status bar and the bottom Session section both show elapsed time and volume. The duplication weakens hierarchy and spends scarce screen space without adding a new decision-supporting fact.

**Fix:** Remove the bottom duplicate now that the top bar is persistent, or replace it with per-exercise progress/volume that the status bar cannot provide.

**Suggested command:** `/impeccable distill`

### [P2] Set-deletion Undo is too fragile

**Why it matters:** The Undo action has no explicit 44pt frame, and the single recovery slot is overwritten by a second deletion. It also remains indefinitely, potentially obscuring lower content. This is a poor mismatch between the importance of the recovery action and its affordance.

**Fix:** Give Undo a 44pt target and auto-dismiss the toast after a short interval. Either queue a second deletion or clearly replace the prior recovery target rather than silently invalidating it.

**Suggested command:** `/impeccable harden`

### [P3] Manually added exercises cannot be reordered

**Why it matters:** Exercises append in creation order and cannot be rearranged, so an improvised session cannot reflect a changed training sequence. This is not blocking, but it limits real-world flexibility.

**Fix:** Add native list reordering with an Edit-mode affordance, preserving the existing routine order and persistence behavior.

**Suggested command:** `/impeccable adapt`

## Persona Red Flags

**Casey — distracted mobile user:** Autosave and scene-phase persistence are excellent for interruptions, but Save/Cancel remain top-toolbar actions and the bottom Undo toast can remain indefinitely over the content. The primary recovery affordance is also smaller than the other controls.

**Jordan — first-timer:** The logger is understandable at a glance, but “RPE” is unexplained. “RPE 0–10” gives a range without explaining that it means perceived effort or what a useful value represents.

**Sam — accessibility-dependent user:** Most controls are labeled and meet the 44pt minimum, but the Undo button is an exception. The previous-performance cue uses a small, tertiary caption, which may be difficult to perceive even though it carries decision-relevant context.

## Minor Observations

- Completing a set has no restrained haptic or sensory feedback; the checkmark changes, but the primary repeated success moment is emotionally flat.
- Persisting a draft on every `exercises` change may cause unnecessary SwiftData writes while typing; verify before optimizing.
- Live-session duration is computed from session start, with no direct correction affordance if the user leaves the workout open longer than intended.
- Current source verification contradicts older claims that the rest status is buried at the bottom or that numeric fields are below 44pt: the status bar is in a top safe-area inset, and numeric fields use at least 44pt height.

## Questions to Consider

- If the top status bar already owns live elapsed time and volume, should the bottom Session section become per-exercise progress instead?
- Can RPE be made self-explanatory without adding persistent clutter—perhaps a one-line hint on first expansion?
- Should the repeated completion gesture get one quiet haptic confirmation, consistent with the product’s restrained tone?
