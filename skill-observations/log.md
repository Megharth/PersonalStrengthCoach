# Skill Observation Log

Observations captured during task-oriented work.

### Observation 1: Native audit findings need source verification

**Status:** OPEN
**Date:** 2026-08-16
**Session context:** Impeccable critique of a native SwiftUI workout logger
**Skill:** impeccable
**Type:** open-source
**Phase/Area:** Critique assessment synthesis

**Issue:** An independent native audit produced several accessibility findings that were contradicted by the source, including claims that existing icon-only controls lacked labels. Line drift and treating a web-oriented detector as evidence made those findings look more authoritative than they were.

**Suggested improvement:** Require the synthesis pass to verify every automated or sub-agent finding against the current source before reporting it, explicitly separating deterministic detector output from manual native review, and discard contradicted findings.

**Principle:** Automated or delegated review findings are hypotheses until grounded in the current implementation.

### Observation 2: Native keyboard accessory clutter needs visual verification

**Status:** OPEN
**Date:** 2026-08-18
**Session context:** Workout logger UI refinement
**Skill:** impeccable
**Type:** open-source
**Phase/Area:** Native responsive layout and interaction review

**Issue:** A screenshot review revealed that adding a Done control to each numeric field's keyboard toolbar created a repeated row of Done buttons when multiple fields were present, an issue not surfaced by the existing functional UI tests.

**Suggested improvement:** Add a native visual verification pass for keyboard presentation and accessory views whenever text-field toolbars are introduced, especially on screens containing repeated form rows.

**Principle:** Functional tests should be complemented by visual checks of system-mediated UI, including keyboards, toolbars, sheets, and other repeated native surfaces.

### Observation 3: Unit conversion boundaries must stay explicit in UI state

**Status:** OPEN
**Date:** 2026-08-18
**Session context:** Fixing workout logger weight suggestion and commit display
**Skill:** New skill candidate: native form-state debugging
**Type:** open-source
**Phase/Area:** Data/display boundary diagnosis

**Issue:** A logger passed a display-unit value into a formatter that expected canonical kilograms, causing a pound value to be converted twice; the prompt also remained a placeholder after commit because placeholder text is not field state.

**Suggested improvement:** Add a debugging checklist for forms with canonical and display units: label each value by its unit at every boundary, test one known conversion end-to-end, and verify committed state separately from prompt rendering.

**Principle:** Treat display formatting and input state as separate boundaries, and make units explicit at every conversion boundary.

### Observation 4: Shared (non-worktree) files under review can change mid-review

**Status:** OPEN
**Date:** 2026-08-18
**Session context:** Reviewing PersonalStrengthCoach/WorkoutLoggerViewV2.swift against the Active Set Lane brief, from a git-worktree-isolated agent that had to read the file from the shared main checkout because it didn't exist in the assigned worktree
**Skill:** New skill candidate: native form-state debugging (or a general review-hygiene principle)
**Type:** open-source
**Phase/Area:** Code review process / concurrent-editing detection

**Issue:** A first full Read of the target file showed correct string interpolation (`\(...)`) and a simple V1-matching layout. A later grep/diff pass on the same path (minutes later, same session) showed different content — a literal escaped-backslash bug (`\\(...)` instead of `\(...)`) and additional padding/background changes — because another session was actively editing the file in the shared checkout while the review was in progress. The file's mtime and line count had both changed between the two reads. Nothing in the tool output flagged this; it was only caught by re-reading and diffing before finalizing the report.

**Suggested improvement:** When a review target lives outside the agent's isolated worktree (a shared checkout another session can write to), snapshot `mtime`/line count (or a hash) at the start, and re-check it immediately before writing the final report — re-fetch fresh content if it changed, and note the volatility explicitly in the findings rather than silently trusting the first read.

**Principle:** A review of a file outside your own isolation boundary is a review of a moving target unless you explicitly re-verify freshness right before reporting; treat the first read as provisional, not ground truth.

### Observation 5: Large Dynamic Type needs per-screen verification

**Status:** OPEN
**Date:** 2026-08-18
**Session context:** Visual verification of a native workout logger and dashboard
**Skill:** impeccable
**Type:** open-source
**Phase/Area:** Native responsive layout and accessibility review

**Issue:** A simulator pass at an accessibility content size exposed severe card reflow on a dashboard, while a focused functional test still passed. The logger itself was not captured at that size, so whole-app large-text readiness could not be inferred from a single screen or test.

**Suggested improvement:** Require visual verification at representative large and accessibility content sizes for each changed screen, and record screen-specific outcomes separately from broader app observations.

**Principle:** Dynamic Type regressions are screen-specific visual behavior; functional success and one-screen inspection do not establish whole-app accessibility readiness.


### Observation 6: Source-level layout edits need compile verification

**Status:** OPEN
**Date:** 2026-08-19
**Session context:** Resuming workout logger V2 layout refinement from handoff
**Skill:** impeccable
**Type:** open-source
**Phase/Area:** Native responsive layout implementation

**Issue:** A structural layout edit compiled only after fixing an undefined alignment type and an extra closing brace; focused UI tests could not expose either source-level issue.

**Suggested improvement:** Keep a short compile checkpoint immediately after each structural SwiftUI layout edit, before proceeding to visual or UI-test verification, and treat handoff claims as pre-edit status until rerun.

**Principle:** Source structure must be revalidated after layout refactors because behavioral tests do not cover parser and type-level regressions.


### Observation 7: Forked UI implementations can silently lose recent fixes

**Status:** OPEN
**Date:** 2026-08-19
**Session context:** Post-build review of a SwiftUI workout logger layout fork
**Skill:** impeccable
**Type:** open-source
**Phase/Area:** Native UI refactor review

**Issue:** A copied view used for layout experimentation omitted two recently added interaction safeguards—focus bindings and commit-trigger propagation—even though the copied screen compiled and navigation tests passed.

**Suggested improvement:** When introducing a parallel UI implementation, diff behavior against the canonical implementation and explicitly audit focus, commit, accessibility, persistence, and recent-history changes before wiring it into production. Prefer one canonical implementation where practical.

**Principle:** Compilation and navigation coverage do not establish behavioral parity for a forked UI implementation.


### Observation 8: Nested custom confirmation sheets need dismissal-path review

**Status:** OPEN
**Date:** 2026-08-21
**Session context:** Workout logger confirmation refinement and post-review verification
**Skill:** impeccable
**Type:** open-source
**Phase/Area:** Native confirmation surfaces and verification

**Issue:** A custom confirmation sheet nested inside an already presented editor sheet manually dismissed both layers; an iOS review identified a plausible double-dismiss race that was not covered by the existing UI suite.

**Suggested improvement:** Require confirmation-flow reviews to trace presentation ownership and every dismiss call, and prefer system-managed confirmation surfaces when the requested visual correction can be achieved without replacing native semantics.

**Principle:** Modal correctness depends on presentation ownership and dismissal sequencing, not only on the visible contents of the modal.

### Observation 9: Mine stale xcresult bundles before re-deriving root cause from source alone

**Status:** OPEN
**Date:** 2026-08-24
**Session context:** Investigating an "Invalid frame dimension (negative or non-finite)" runtime warning plus a "Test crashed with signal kill" failure reported for a SwiftUI weight TextField during a delete-then-retype UI test step
**Skill:** ios-expert (general debugging methodology, not tied to one skill)
**Type:** open-source
**Phase/Area:** Root-cause investigation workflow

**Issue:** The task was framed as pure code inspection ("analyze code, identify minimal fix"), and reading WorkoutLoggerView.swift alone produced a plausible but unconfirmed hypothesis (a unit-converting Binding driving a FormatStyle TextField). The project's `.build/` directory (outside the git worktree, at the stable repo root) turned out to contain over a dozen prior `*.xcresult` bundles from earlier debugging attempts at this exact issue. `xcrun xcresulttool get test-results tests/activities --path <bundle>` against them gave the exact failing test name, the literal runtime-warning string, and — critically — the precise activity sequence (tap field → warning fires → type '' → type '185' → crash) that pinpointed the failure to the weight field specifically and to the moment right after retyping, not merely "somewhere in this file."

**Suggested improvement:** Before or alongside static code review for a reported runtime warning / crash / test failure, check for existing `*.xcresult` bundles (commonly under `.build/`, `DerivedData`, or a CI artifact path) and query them with `xcresulttool get test-results tests` (to find the failing test and diagnostic strings) and `... activities --test-id <id>` (to get the ordered UI-action timeline around the failure) before forming a root-cause hypothesis from source alone. This converts a guess into an evidence-backed diagnosis and can reveal that other agents/sessions already attempted (and failed at) fixing the same issue, which is useful context to surface.

**Principle:** When a task references a specific runtime diagnostic or test failure, look for the artifact that already recorded it (test result bundles, logs, crash reports) before reconstructing the failure purely from reading source — the artifact often pinpoints the exact trigger sequence that static reading can only guess at.

### Observation 10: Diagnose native form races before adding dependencies

**Status:** OPEN
**Date:** 2026-08-31
**Session context:** Investigating workout logger sets that fail to persist after editing
**Skill:** New skill candidate: native form-state debugging
**Type:** open-source
**Phase/Area:** Dependency evaluation and root-cause diagnosis

**Issue:** A report of missing repeated form input prompted consideration of an external input library, but source inspection identified an interaction-order race between a locally buffered field and a same-tap save/advance action.

**Suggested improvement:** Add a dependency-triage step to native form debugging: compare field commit semantics, focus/dismissal ordering, view identity, and persistence timing before evaluating third-party replacements; prefer a focused native fix when the defect is local and the platform APIs already cover the need.

**Principle:** Do not introduce a dependency to compensate for a diagnosable state-commit race in a native control.

### Observation 11: Late-arriving wearable data requires postponing HKWorkout finalization

**Status:** OPEN
**Date:** 2026-09-08
**Session context:** Implementing Apple Health workout recording with third-party wearable (Amazfit) data enrichment
**Skill:** New skill candidate: HealthKit Integration Patterns
**Type:** open-source
**Phase/Area:** HealthKit Workout Builder lifecycle & third-party wearable sync

**Issue:** Third-party wearables (e.g. Amazfit via Zepp, Garmin, Whoop) sync data to Apple Health asynchronously with unpredictable latency, often requiring the user to open the companion app first. If the workout session is finalized immediately via `HKWorkoutBuilder.finishWorkout()` at save time, late-arriving samples cannot be attached to that `HKWorkout` record through the standard builder pipeline.

**Suggested improvement:** Document the pattern: keep the `HKWorkoutBuilder` open (or delay finalizing) while presenting a manual "Sync Biometrics" step to the user, allowing samples written by other apps to be fetched and attached via `builder.addSamples()` before calling `finishWorkout()`. Provide a fallback cleanup (auto-finalize on view dismissal) to ensure workouts aren't left unfinalized.

**Principle:** When integrating with external data sources that sync asynchronously with unpredictable timing, defer finalizing write-once containers (like `HKWorkout`) until after a user-initiated sync check, with an automatic finalizer as a fallback on teardown.
