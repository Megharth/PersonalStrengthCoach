---
target: workout logger
total_score: 27
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 3
timestamp: 2026-08-17T02-11-38Z
slug: personalstrengthcoach-workoutloggerview-swift
---
# Workout Logger Critique

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|---:|---|
| 1 | Visibility of System Status | 2/4 | Rest countdown, elapsed time, and volume live at the bottom of an expanding list. |
| 2 | Match System / Real World | 4/4 | Set types, RPE, weight × reps, routines, and previous performance match lifter language. |
| 3 | User Control and Freedom | 2/4 | Draft/routine replacement is guarded, but set deletion has no undo or confirmation. |
| 4 | Consistency and Standards | 3/4 | Strong native SwiftUI patterns; input sizing and destructive-action treatment diverge. |
| 5 | Error Prevention | 2/4 | Weight is clamped, but reps/RPE constraints are not visibly enforced while typing. |
| 6 | Recognition Rather Than Recall | 4/4 | Previous performance appears beside the set it informs; routine and draft recovery are discoverable. |
| 7 | Flexibility and Efficiency | 3/4 | Routines, prefill, and copy-forward defaults are excellent; advanced shortcuts are limited. |
| 8 | Aesthetic and Minimalist Design | 2/4 | Every set exposes RPE, set type, and a picker, making the common path feel spreadsheet-dense. |
| 9 | Error Recovery | 3/4 | Save errors preserve the form and explain failure, though recovery guidance is generic. |
| 10 | Help and Documentation | 2/4 | RPE and set types have no inline explanation or scale hint. |
| **Total** | | **27/40** | **Acceptable: solid native foundation, significant task-flow improvements needed.** |

## Design Specificity Verdict

This is clearly authored for Personal Strength Coach rather than category-interchangeable boilerplate. The native List/Section structure, mint completion signal, prior-performance context, routine entry, and resumable drafts express the product's quiet, resilient training-companion brief. The weakness is not identity; it is that the highest-stakes moments of the workout—resting, entering primary numbers, and returning after interruption—do not receive the same compositional priority as the rest of the system.

The deterministic web detector returned `[]`. That is not evidence that the native surface is defect-free: the detector is built for HTML/CSS/JS and does not understand SwiftUI. Assessment B's native audit corroborated the fixed-field and performance concerns, but its claimed missing labels on completion/delete controls are false positives: the completion button and exercise removal button already have explicit accessibility labels, and the set deletion swipe action uses a visible `Label("Delete set", systemImage: "trash")`.

Browser visualization was skipped because this is a native SwiftUI target. No Simulator screenshot or physical-device evidence was collected in this critique run.

## Overall Impression

The logger has unusually good product logic for a workout screen: it remembers the user's history, copies sensible defaults, starts rest automatically, and survives interruptions. But the visible experience becomes progressively less calm as a session grows. The rest timer is treated as a footer statistic instead of a live instrument, and every set row asks the user to scan secondary controls before completing the primary action. The single biggest opportunity is to make the active set—and the recovery state immediately after it—visibly dominant.

## What's Working

- **Resumable drafts:** `loadDraftIfNeeded` and `persistDraft` directly address gym interruptions and create trust without extra ceremony.
- **Contextual efficiency:** `PreviousSetEngine`, routine drafts, and `nextSetDefaults` minimize typing for a repeat lifter.
- **Completion feedback:** Tapping the completion control both changes state and starts rest, creating a tight, useful loop.
- **Native foundation:** NavigationStack, List, sheets, confirmation dialogs, semantic colors, SF Symbols, and system text styles align with the documented iOS direction.

## Priority Issues

### [P1] The rest timer is buried below an unbounded exercise list

- **What:** The `Session` section (`WorkoutLoggerView.swift:198–206`) appears after every exercise section, so the countdown scrolls away as the workout grows.
- **Why it matters:** A lifter needs the timer while resting, not after hunting for it. This turns the core recovery signal into a memory and navigation tax.
- **Fix:** Promote active rest to a persistent, compact status surface—such as a pinned list header/footer or a toolbar-adjacent bar—with elapsed time and volume as secondary details. Consider a Live Activity only if the product is ready to support that broader surface; do not make it a prerequisite for fixing in-app visibility.
- **Suggested command:** `/impeccable layout`

### [P1] Primary numeric inputs are not robust at touch and Dynamic Type sizes

- **What:** The RPE field uses a fixed width (`WorkoutLoggerView.swift:492–496`), while `NumericFieldInt` and `NumericFieldDouble` cap fields at 90 points (`:560–570`). They do not establish a 44-point minimum height or an adaptive row strategy.
- **Why it matters:** These are the controls hit repeatedly with one hand. Large text can clip or make the row feel cramped, and narrow fields reduce confidence during a fast set entry.
- **Fix:** Give every input a 44-point minimum hit height, add explicit contextual accessibility labels to weight/reps fields (including set number and unit), and let the row reflow at accessibility content sizes rather than relying on fixed widths. Verify on iPhone, iPad, and large Dynamic Type.
- **Suggested command:** `/impeccable adapt`

### [P1] Secondary controls overwhelm the common set-entry path

- **What:** RPE and the Set Type picker are rendered for every set (`WorkoutLoggerView.swift:492–513`), even when the default working-set path needs neither.
- **Why it matters:** The most frequent action—enter weight, enter reps, mark complete—competes with two lower-frequency decisions. Repetition multiplies the scan cost across an entire workout.
- **Fix:** Keep weight, reps, and completion visible. Put RPE and Set Type behind a per-set “More” disclosure or a compact details sheet, preserving the current values once chosen. Add a short “RPE 0–10” hint at the point of first use.
- **Suggested command:** `/impeccable distill`

### [P2] Previous-performance context is duplicated

- **What:** The exercise header's full `previousSummary` (`WorkoutLoggerView.swift:460–465, 540–542`) repeats the per-set “Previous” captions (`:514–520`).
- **Why it matters:** The same fact appears twice in a dense card, increasing scanning without adding decision support.
- **Fix:** Keep the per-set value beside the input it informs. Reduce the header to a compact “Last trained [relative date]” cue, or remove it when the per-set references are present.
- **Suggested command:** `/impeccable distill`

### [P2] Destructive set deletion has no lightweight recovery

- **What:** Swipe-to-delete removes a set immediately (`WorkoutLoggerView.swift:522–528`), while whole-draft discard and routine replacement are confirmed.
- **Why it matters:** The asymmetry makes an accidental swipe more costly than an intentional draft discard, and a set can represent meaningful history.
- **Fix:** Add an undo path for deletion (preferred for a fast logger), or use a confirmation only when deletion is irreversible. Keep the current no-full-workout-implicit-delete behavior.
- **Suggested command:** `/impeccable harden`

## Cognitive Load

Five checklist failures are present: no progressive disclosure for secondary set controls; duplicated previous-performance information; session monitoring separated from the active entry context; weak visual distinction between primary and secondary fields; and a rest countdown that must be remembered or hunted for. This is **high cognitive load at the resting/entry transition**, even though the underlying data model is thoughtful.

## Emotional Journey

The flow begins confidently: title/date and routine entry are familiar, and smart defaults reduce effort. The strongest moment is set completion: the mint state change and automatically started rest timer provide immediate confirmation. The emotional valley arrives after several exercises, when the timer disappears below the list and the row remains visually dense. Interruption recovery is a major trust payoff because the draft returns intact. Save failures preserve input, but the generic “Try again” copy leaves uncertainty about what to do next.

## Persona Red Flags

**Alex — impatient power user**
- Repeat sessions still expose RPE and Set Type on every row, increasing taps/scanning for a user who usually needs only weight, reps, and completion.
- No compact, persistent rest control means Alex must scroll or remember the countdown between sets.

**Sam — accessibility-dependent user**
- Fixed-width RPE/number fields can become cramped at accessibility Dynamic Type sizes.
- Weight and reps fields lack explicit set-aware accessibility labels in `NumericFieldInt`/`NumericFieldDouble`, unlike the completion and RPE controls.

**Casey — distracted mobile / first-time user**
- RPE and Set Type appear without an inline explanation, so domain jargon arrives before the user has established a basic logging rhythm.
- The growing list of near-identical rows makes the primary action less obvious as the session continues.

## Minor Observations

- `Cancel` versus `Discard` is a good contextual toolbar label.
- The timer task updates `now` every second even in edit mode, where the Session section is not shown; gate it to new-session logging to avoid needless updates.
- `PreviousSetEngine.mostRecentPerformance` is computed in the `ForEach` view expression; consider caching per exercise/session if workout history becomes large.
- Save-error copy should preserve the current draft and offer a specific next step where the underlying error is known.
- Conditional large-title treatment could better distinguish a new top-level logging session from editing an existing workout, but this is polish rather than a priority.

## Questions to Consider

- If rest is the most time-sensitive number in the flow, why is it the only major session signal that scrolls away?
- Which percentage of users actually changes RPE or Set Type on a typical set, and should everyone pay that visual cost?
- Can the logger feel like a calm instrument while showing five controls per set, or should the common path be deliberately narrower?
- Is a one-tap undo better aligned with gym speed than confirmation dialogs for set deletion?
