# Personal Strength Coach — Feature Spec

**Status:** Active · **Last updated:** 2026-08-15

This document proposes features and improvements for Personal Strength Coach, an
on-device iOS strength-training tracker (SwiftUI + SwiftData, Apple frameworks
only). It is organized in three parts:

1. **Product analysis** — what exists today and where the gaps are.
2. **Proposed features** — prioritized, grouped by theme.
3. **Expert reviews** — appended opinions from the UI/frontend and
   health-algorithm reviews.

Guiding constraints (from `CLAUDE.md`): Apple frameworks only, no third-party
dependencies, on-device data, SwiftData schema changes must bump
`AppSchemaV1`/`AppMigrationPlan`, and non-trivial calc/parse changes get focused
XCTests.

---

## 1. Product analysis

### What the app does today

- **Logging** — manual workout logging (`WorkoutLoggerView`) with an exercise
  picker over a seeded library + user-created custom exercises; newly added
  exercises prefill editable sets from the most recent matching workout; Strong
  app import (CSV/JSON/shared text).
- **Recovery** — read-only HealthKit sync (`HealthKitService`) of the last 15
  days of sleep, HRV, resting HR, and body mass into `DailyRecovery`.
- **Derived insight** — pure engines (`TrainingEngines.swift`): a 0–100
  readiness score, per-muscle recovery %, weekly volume, Epley estimated 1RM,
  PR detection, and a rules-based next-workout suggestion.
- **Coach** — a chat screen that POSTs training context to an AI proxy and
  falls back to the local recommendation when the proxy is unset.
- **Data** — JSON export and "delete all local data" in Settings.

### Current gaps and recently resolved foundations

**Recently resolved trust / correctness work (2026-08-11)**
- Home, Dashboard, workout-detail, and exercise-detail coaching/trend content now
  comes from real readiness, recommendation, PR, volume, and estimated-1RM data.
  The Dashboard shows an explicit empty state until a weighted exercise has usable
  history in at least two recent weekly windows.
- Manual workouts now capture elapsed duration, and Strong CSV imports back-fill
  duration when the export supplies it (`0cc6dd7`).
- Readiness treats zero HRV/resting-HR values as missing, rejects stale/future
  "today" data, clamps future-dated muscle-recovery elapsed time, and exposes
  low/medium/high confidence. PR detection rejects implausible jumps over 40% and
  returns deterministic, de-duplicated records (`1bd707e` plus current P0 work).

**Remaining data model limits**
- **Routines/templates are now implemented**: saved routines can store ordered
  exercises with target sets/reps/optional weight, and the workout logger can
  start from a saved routine.
- No **rest timer**, **RPE/RIR**, **warmup vs working set** flag, or **set type**
  (drop set, failure) — limits both UX and analytics quality.
- No **bodyweight/unit preference** (kg hardcoded throughout), no per-exercise
  notes, no **workout-in-progress** state (logger is a one-shot sheet; a crash
  or backgrounding loses everything).

**Analytics depth**
- Basic per-workout and weekly estimated-1RM trends now exist, but there is still
  no volume-per-muscle-per-week, consistency/streak metric, rep-max breakdown,
  confidence band, or dedicated PR history view.
- Muscle recovery remains a flat 72h clock. Readiness now handles missing/stale
  data and reports confidence, but still lacks dispersion-aware z-scores, sleep
  debt, and workload normalization. (See health-algorithm review below.)

**Engagement / retention**
- No **notifications** (workout reminders, "you're recovered", PR celebration).
- No **Home Screen widgets** or **Lock Screen widgets** for readiness/next
  workout — a natural fit for this data.
- No **Apple Watch** companion or **Live Activity** for an in-progress workout.
- No **onboarding** or HealthKit permission priming; sync just fires on launch
  (`RootView.swift:27`) and shows an error alert if denied.

**Navigation**
- **6 tabs** is heavy for a bottom bar; "Today" and "Dashboard" overlap, and
  Settings rarely needs a permanent tab slot.

---

## 2. Proposed features (prioritized)

### P0 — Foundational / trust
- [x] **Replace hardcoded content with real computations.** Completed 2026-08-11.
  Home coaching uses readiness confidence and local recommendations; Dashboard
  strength trends use recent weekly estimated 1RM with a no-history state;
  workout and exercise notes use actual PR, volume, set, and progression data.
- [x] **Fix workout duration.** Completed in `0cc6dd7`. Manual logging captures
  bounded elapsed time, and Strong CSV imports use source duration when present.
- [x] **Routines / templates.** Completed 2026-08-11. Added `Routine` /
  `RoutineExercise` models, versioned SwiftData migration/export coverage,
  routine create/edit/delete UI, and start-from-routine logging with prefilled
  editable sets.
- [x] **Edit and delete logged workouts.** Completed 2026-08-13 — scoped in §4.1,
  shipped as one slice (delete + edit together). `WorkoutLoggerView` is now
  dual-mode: it prefills from an existing workout and diffs its sets on save,
  preserving `calories`/`notes` by reusing the model. Delete is available from
  History (swipe) and from a workout's detail view, both behind a confirmation.
  Duration became editable, but **only when editing** — new workouts keep the
  automatic session timer, and both paths clamp through
  `WorkoutTimerEngine.clampedMinutes`.

### P1 — Logging experience
4. **In-workout session** with rest timer and running volume. Persist a
   `WorkoutInProgress` so backgrounding/crash doesn't lose data. *(The
   "previous set" reference and editable prefill were split out of this item;
   see 4a, shipped independently of the timer and persistence work.)*
   - **4a. Previous-set reference + editable prefill in the logger** — shipped
     2026-08-15; scoped in §4.2.
5. **RPE/RIR + set type** on `ExerciseSet` (warmup, working, drop, failure).
   Unlocks autoregulation and cleaner volume math (exclude warmups).
6. **Plate calculator** and **unit preference** (kg/lb) app-wide.

### P1 — Analytics
- [ ] **Per-exercise progress screen** *(partially implemented)*. Current screen
  shows best set, per-workout estimated-1RM history, and computed progression
  notes. Remaining: real date/value axes, rep-max estimates, volume over time,
  confidence bands, and a PR timeline.
- [ ] **Weekly volume per muscle group** vs. targets (volume landmarks — see
  health review), plus a training-consistency / streak metric.
- [ ] **PR history view** — a dedicated list of all PRs over time, celebrated.

### P1 — Platform integration
10. **Home Screen + Lock Screen widgets** (WidgetKit): today's readiness, next
    workout, weekly volume, days since last session.
11. **Local notifications**: recovery-based "ready to train" nudge, workout
    reminders tied to routines, PR celebration.
12. **Live Activity** for an in-progress workout (rest timer on Lock Screen /
    Dynamic Island).

### P2 — Coaching & engagement
13. **Deload / overreaching detection** and autoregulated next-set suggestions
    (see health review — ACWR, monotony/strain).
14. **Richer AI coach**: feed real trend data + recent workouts into the proxy
    context; suggested prompts; safe offline fallback (already present — keep).
15. **Apple Watch companion** for logging sets and readiness at a glance.

### P2 — Polish
16. **Onboarding + HealthKit priming** with a pre-permission explainer screen.
17. **Consolidate tabs** (e.g. merge Today/Dashboard; move Settings behind a
    profile button). Target 4 tabs.
18. **Haptics, transitions, empty states, Dynamic Type & VoiceOver** pass.

---

## 3. Expert reviews

_The following sections are preserved as point-in-time specialist reviews. Some
P0 findings described below were resolved on 2026-08-11; the checklists and
status notes in Section 2 are authoritative for current implementation status._

### 3.1 UI / Frontend review

_From the `ui-frontend-expert` agent. Grounded in the current source; no files
were modified._

#### Biggest UX/UI problems (with citations)

**Fabricated data presented as real — a trust problem, not just polish**
- `RootView.swift:78` — `TrendChart(title: "Strength trend", points: [92, 96, 98, 101, 105, 104, 108], ...)` is a hardcoded array shown on the Dashboard next to real Sleep/HRV charts. Highest-priority fix — showing fake numbers next to real ones is worse than showing nothing.
- `RootView.swift:64` — "Coach summary" `CoachCard` has a static string regardless of actual recovery/muscle data, even though `RecoveryEngine`/`RecommendationEngine` already compute the real values one line above.
- `WorkoutDetailView`, `RootView.swift:123` — "Coach notes" is the same static sentence for every workout, even though `PerformanceEngine.personalRecords` already computes real per-workout facts.

**A real data-integrity bug that surfaces as broken UI**
- `WorkoutLoggerView.swift:79` — `Workout(..., durationMinutes: 0)`. There is no session timer, so every manually logged workout saves `durationMinutes: 0` and `calories: 0`. `WorkoutHistoryView` (`RootView.swift:91`) and `WorkoutDetailView` (`RootView.swift:115`) then show "0 min" / "0 kcal" for every hand-logged workout. This is a missing feature (no elapsed-time capture) that quietly corrupts two visible metrics.

**Tab bar will silently break navigation on iPhone**
- `RootView.swift:14-21` — 6 `.tabItem`s. SwiftUI's tab bar auto-collapses items beyond 4 visible + a "More" list on iPhone widths. Coach and Settings are the likely candidates pushed behind "More" — the AI coach, a headline feature, could require an extra tap through a generic list. Resolve before adding more tabs.

**No empty/first-run states outside the logger**
- Only `WorkoutLoggerView.swift:38` uses `ContentUnavailableView`. `WorkoutHistoryView` renders a bare empty `List` for a new user; `DashboardView`/`RecoveryView` render `MetricCard`s showing literal `"0.0"`/`"0"`, which reads as "you did zero volume" rather than "no data yet."
- `RecoveryEngine.readiness` returns a "Connect Apple Health" message when `today == nil`, but it only surfaces as small secondary text inside `ReadinessCard.factors` — easy to miss as the real explanation for a 50-score ring.

**No permission priming for HealthKit**
- `RootView.swift:23-28` — `.task { await syncHealthKit() }` fires the system Health prompt cold on first launch. Apple's guidance favors a short "why we need this" screen first, since users who reflexively deny a surprise prompt can't easily be re-prompted.

**Accessibility gaps are systemic**
- `Components.swift:28` — `TrendChart` hides both axes with no labels/values and no `.accessibilityChartDescriptor`, so VoiceOver users get effectively nothing (affects 3 Dashboard charts + `ExerciseDetailView`).
- `WorkoutLoggerView.swift:110,116` — icon-only set-remove/exercise-remove buttons are `.borderless`, default SF Symbol size, no `.accessibilityLabel`, well under the 44×44pt minimum target; VoiceOver announces them ambiguously.
- `Components.swift:6` — `ReadinessCard` collapses Yellow and Red into identical "Train with intent" copy, so text alone can't distinguish moderate from poor readiness (bad for colorblind users).
- No `.sensoryFeedback`/haptics anywhere — saving a workout, hitting a PR, and completing sets all pass silently.

**Logging flow is a static form, not a workout companion**
- `WorkoutLoggerView` has no rest timer, no "last time" reference per exercise (the data exists via `ExerciseSet.normalizedExercise` + `workout.date` but isn't surfaced), and defaults every new set to `weight: 0, reps: 8` (indistinguishable from "not yet filled in").

#### Concrete improvements & new features (iOS-native)

**Fix trust/correctness first**
- Replace `RootView.swift:78`'s hardcoded array with a real series (e.g. weekly `PerformanceEngine.weeklyVolume`, or best estimated-1RM per week on a top lift); show the chart's empty state when there's no history.
- Generate "Coach summary" and "Coach notes" from the already-computed `ReadinessResult`/`personalRecords`, following the established "call `AIInsightService`, fall back to local engine text" pattern in `CoachView.send()`. Omit the section when nothing is computed rather than showing filler.
- Add a lightweight session timer to `WorkoutLoggerView` (start on sheet appear or explicit Start/Finish) so `durationMinutes` stops being `0`.

**Tab bar restructuring (6 → 4–5)** — flag as a product decision before restructuring, since it changes where Recovery content lives:
- **Today** (Home), **Train** (History + the "+" log/import menu), **Trends** (merge Dashboard + Recovery via a segmented control or sectioned scroll), **Coach**, and move **Settings** off the tab bar into a toolbar gear on Today.

**Empty, loading, and permission states**
- `ContentUnavailableView` for zero-workout `WorkoutHistoryView` with a primary action that opens the logger.
- Dedicated "Connect Apple Health" `ContentUnavailableView` on Dashboard/Recovery when there's no `DailyRecovery` data, instead of zero-filled `MetricCard`s.
- One-time dismissible priming screen before the first `HealthKitService.sync` (store a "has primed" `@AppStorage` flag).

**Logging flow enhancements (biggest value-add)**
- **Previous-set reference** in `ExerciseLoggerCard`: fetch the most recent set(s) for that `normalizedExercise` and show "last: 60kg × 8" as secondary text.
- **Rest timer**: in-sheet countdown after a set is marked complete, optionally promoted to an ActivityKit Live Activity/Dynamic Island — the single most "app feels alive" addition, but larger effort.
- **Plate math**: a pure `PlateMathEngine` (bar + plate set → per-side plates) fits the existing stateless-engine architecture; surface inline next to the weight field.
- Default new sets to blank/nil display rather than `weight: 0, reps: 8`.

**Haptics & motion (quick, native, low-risk)**
- `.sensoryFeedback(.success, trigger:)` on workout save, new-PR detection, set added/removed.
- `.animation(.easeInOut, value:)` on the readiness ring fill, muscle-recovery tiles, and chart updates; gate with `@Environment(\.accessibilityReduceMotion)`.

**Chart accessibility (`Components.swift:26-29`)**
- Don't fully hide axes — show a Y axis with 2–3 gridline labels and a sparse X axis (first/last dates).
- Add `.accessibilityChartDescriptor` / per-series labels summarizing trend direction and range.
- Handle `points.isEmpty` and `points.count == 1` explicitly.

**Small accessibility/touch-target fixes**
- Explicit `.accessibilityLabel` + 44×44pt hit area on the icon-only buttons (`WorkoutLoggerView.swift:110,116`).
- Per-row accessibility labels on `NumericFieldInt`/`NumericFieldDouble` including set number and exercise.
- Differentiate Yellow vs Red readiness copy in `ReadinessCard`.

#### Prioritization

**Quick wins (small diffs, high value, no architecture change)**
- Replace hardcoded strength-trend array with a real series (`RootView.swift:78`).
- Generate real Coach-summary/Coach-notes copy from existing engine output.
- Add `ContentUnavailableView` empty states to History, Dashboard, Recovery.
- Add `.sensoryFeedback` haptics on save/PR/set-add.
- Accessibility labels + touch targets on icon-only buttons.
- Differentiate Yellow/Red readiness copy.
- Real axis labels on `TrendChart`.

**Medium effort**
- Tab bar consolidation (6 → 4–5, needs a product decision).
- HealthKit permission-priming screen.
- "Last time" reference in the logger per exercise.
- Session duration capture (fixes the `durationMinutes: 0` bug).
- Chart VoiceOver descriptors.

**Larger efforts (separate spec items)**
- Live in-workout rest timer with ActivityKit Live Activity/Dynamic Island.
- Plate math engine + UI (+ bar-weight/unit setting).
- Home Screen widget (WidgetKit) for today's readiness.
- Superset/circuit logging (schema change via `AppSchemaV1`/`AppMigrationPlan`).

### 3.2 Health / algorithm review

_From the `health-algorithm-expert` agent. Advisory only; no files modified.
Frame every score below as a wellness/training-load indicator, not a medical or
diagnostic claim._

#### Critique of current algorithms

**Readiness score (`RecoveryEngine.readiness`)**
- **Divide-by-zero / NaN silently becomes a score, not a warning.** `HealthKitService.sync` can store a `DailyRecovery` row where `hrv == 0` or `restingHeartRate == 0` (sample not synced, watch not worn). Then `rhrBase / 0 = .infinity → min(20, inf) = 20` (looks like a perfect RHR from missing data); if `rhrBase == 0` too, `0/0 = NaN` and `max(0, .nan)` returns `0` (worst-case). The same missing-data condition can swing the score to either extreme — the most concrete bug to fix first. Same applies to the HRV ratio if `hrvBase == 0`.
- **`recoveryDays.first` is treated as "today" with no recency check.** If HealthKit produced no recent sample, `.first` may be days old and is silently shown as today's readiness. Meanwhile the "yesterday load" term uses real wall-clock `now`, so it can be inconsistent with the stale "today" date.
- **Baseline has no dispersion, no minimum sample size, and mixes zero-filled days into the mean.** A flat 14-day mean with no min-N gate and no SD means a night 2 SD below baseline scores the same as one 0.1 SD below unless it crosses the arbitrary 30-point cap. HRV is right-skewed and individual — a raw linear ratio without log-transform or z-scoring is not how the literature (Plews et al., 2013) handles it.
- **Sleep component ignores debt/consistency** and treats 8h as a universal target; one great night fully compensates for a week of debt.
- **Weights (30/30/20/20) and load thresholds (4k/8k kg) are unsourced magic numbers.** Raw kg ignores bodyweight, exercise selection, and session RPE — a 4,000 kg leg day and 4,000 kg of overhead pressing get the same bonus.
- **No confidence/insufficient-data output.** Once any row exists, it returns a fully-formed 0–100 score that looks as trustworthy as one built on 14 clean days.

**Muscle recovery (`RecoveryEngine.muscleRecovery`)** — `min(100, Int(hours / 72 * 100))`
- Pure time-since-last-set: one set of curls "fatigues" biceps identically to a 25-set arm day. Recovery is a function of accumulated stimulus, not just elapsed time.
- Fixed 72h for every muscle ignores documented differences (calves/forearms recover faster than quads/back).
- **No lower-bound clamp** — a future-dated log makes `hours` negative and renders a negative recovery %.
- Only looks at the single most recent session, ignoring cumulative fatigue in the window.
- Uses crude substring matching with equal weight across all muscles per set (no primary/secondary fraction).

**Estimated 1RM (Epley only)** — `weight * (1 + reps/30)`
- Loses accuracy outside ~1–10 reps with no rep-range guard — a 20-rep AMRAP produces a wildly inflated 1RM fed straight into PR detection.
- Single formula, no ensemble; formulas diverge most at high reps.
- No RPE/RIR field, so a true-failure 5RM is equated with a 5-rep set left 4 in reserve.
- No confidence band on the displayed e1RM trend.

**PR detection (`PerformanceEngine.personalRecords`)**
- No outlier/typo rejection: a 500 kg-instead-of-50 entry becomes a permanent PR that suppresses future PR notifications and corrupts every downstream e1RM/trend/coach payload.
- 1RM-based and volume-based PRs are conflated as equally meaningful.
- `Array(Set(records))` discards ordering (unstable render order).
- Every first-ever exercise auto-triggers a "PR" (true but not useful signal).

**Next workout (`RecommendationEngine.nextWorkout`)**
- Hardcodes 3 of 14 muscle groups (chest/quads/upper back); ignores hamstrings, glutes, delts, arms, core.
- Single global `>= 70` threshold, no split/goal/day customization.
- Fully deterministic on the already-flawed `muscleRecovery`; errors compound. No weekly-volume-balance accounting.

**HealthKit sync (`HealthKitService.sync`)**
- HRV/RHR are simple same-day means with no outlier rejection — one garbage HRV sample pulls the whole day.
- Fixed 15-day `.now`-anchored backfill, re-fetched every launch (no incremental sync); caps baseline at 14 days.
- Averaging multiple same-day HRV SDNN readings blends post-exercise elevated readings with resting ones (no time-of-day filtering).
- Doesn't distinguish denied authorization from "no data yet."

#### Improved algorithms

**Readiness — baseline-relative, dispersion-aware, gap-safe.** Replace flat means with rolling mean + population SD (min-N gated), and switch each component to a z-score-based saturating transform:
```
z_metric = (today.value - baseline.mean) / baseline.sd    // guard sd > epsilon
component_score = clamp(50 + z_metric * scaleFactor, 0, 100)
```
- **HRV**: log-transform (`ln`) before baselining (raw HRV is right-skewed); note the app reads SDNN, not RMSSD — label precisely. Require ≥5–7 valid baseline days before a z-score; below that report `confidence: .low`.
- **RHR**: same z-score, inverted sign (lower = better).
- **Sleep**: score against the user's own rolling sleep need + a cumulative sleep-debt term, not a fixed 8h.
- **Load**: replace raw-kg thresholds with an acute:chronic workload ratio (ACWR) term.
- **Guard every division**; treat `value == 0` as missing, not zero (a 0 bpm/ms reading is impossible — filter at the HealthKit layer).
- **Emit a confidence field** (`.high` ≥7 valid days, `.medium` 3–6, `.low` <3) and let the UI visibly downweight low-confidence scores.

**Muscle recovery — volume-weighted exponential decay per muscle:**
```
fatigue(muscle, t) = Σ_sessions volumeLoad(session, muscle) * exp(-Δt_hours / τ_muscle)
recovery% = 100 * (1 - clamp(fatigue / fatigueCapacity, 0, 1))
```
- `volumeLoad` = Σ over the muscle's working sets of `weight * reps * muscleContributionFraction` (e.g. bench: chest 1.0, front delts 0.4, triceps 0.5).
- `τ_muscle` varies by group (~24–36h small/fast, ~48–72h large compound), tunable per user.
- `fatigueCapacity` scales with training age/typical volume.
- Clamp elapsed time at `max(0, hours)` to kill the negative-% bug.
- Even a simplified two-tier version (decaying volume-load sum + per-muscle τ table) fixes the "1 set == 25 sets" and "fixed 72h" problems without a large lift.

**Acute:Chronic Workload Ratio (ACWR)** — from existing `Workout.volume`:
```
acuteLoad   = EWMA(dailyVolume, halflife: 7 days)
chronicLoad = EWMA(dailyVolume, halflife: 28 days)
ACWR = acuteLoad / chronicLoad
```
Sweet spot ≈ 0.8–1.3; >1.5 is the commonly cited spike zone (treat as a wellness heuristic, not clinical). Use EWMA to avoid window-boundary jumps. Replaces the 3-tier load bonus and can power an independent "load spike" flag.

**Deload / plateau detection** — combine three signals, surface as a *suggestion*:
1. Volume trend: ACWR persistently >1.3 for 2+ weeks with flat/declining chronic load.
2. e1RM stagnation: rolling regression slope of e1RM per key lift ≤ 0 over 3–4 weeks.
3. Recovery drift: 3+ consecutive days of negative RHR/HRV z-score trend.

**HealthKit ingestion hardening — complete 2026-08-12**
- Reject physiologically impossible samples before averaging (RHR ~30–120 bpm, HRV SDNN ~1–200 ms, sleep 0–16h).
- Use median/trimmed mean for multi-sample days; filter exercise-artifact readings.
- Store per-day sample counts (`hrvSampleCount`, etc.) so the engine can distinguish "0 = no data" from "0 = genuinely zero". **Storage only** — `RecoveryEngine` and the UI do not read these fields yet; wiring them into confidence output remains open.
- Surface knowable HealthKit states truthfully: unavailable, not determined, synced, no readable data, or failed, without falsely claiming read denial when iOS cannot expose that state.
- Body mass is same-day only (no carry-forward), so `bodyMassSampleCount == 0` means "not weighed that day".
- Caveat: `DailyRecovery` rows written before this change backfill all sample counts to `0` and the 15-day sync window never revisits them, so pre-upgrade history older than 15 days will read as zero-confidence once a consumer exists.

**Better e1RM**
- Rep-range-appropriate formula selection or an Epley+Brzycki ensemble (`Brzycki: weight * 36/(37-reps)`); exclude sets with reps > ~12 from e1RM/PR logic.
- If an RPE/RIR field is added (`Models.swift` schema bump), use an RPE-adjusted formula.
- Show e1RM as a trend line with a shaded confidence band (~±5–10%).

#### New health/analytics features (rough cost-vs-payoff order)

1. **ACWR / load-spike indicator** — pure derivative of existing volume, high signal.
2. **Volume landmarks (MEV/MAV/MRV) per muscle** — weekly hard sets vs. literature-informed ranges; flag under-stimulated / over-MRV muscles. Directly strengthens `nextWorkout`, which currently ignores weekly dose. (Present as a coaching heuristic, not RCT-validated.)
3. **e1RM trend with confidence band + stagnation flag.**
4. **Training monotony & strain (Foster)** — `monotony = mean(dailyLoad)/SD(dailyLoad)`, `strain = weeklyLoad * monotony`; complements ACWR, cheap from existing data.
5. **Sleep debt (cumulative)** vs. the user's own baseline need.
6. **HRV-guided daily traffic light** — a standalone single-metric HRV-vs-baseline flag (strongest evidence base), distinct from the composite score.
7. **Body-mass trend smoothing** — `weightKg` is ingested but unused; a 7-day moving average.
8. **PR data-entry sanity guard** — engine-side rejection of implausible jumps over 40% is complete; a user-facing confirmation flow remains open.

#### Prioritization & HealthKit data requirements

| Priority | Item | Status | New HealthKit types? |
|---|---|---|---|
| P0 (correctness) | Guard divide-by-zero/NaN in readiness; clamp negative recovery hours; PR sanity guard | **Complete — 2026-08-11** | None |
| P0 (ingestion) | Reject physiologically impossible HealthKit samples before storage | **Complete — 2026-08-12** | None |
| P0 | Confidence/insufficient-data output (min-N baseline gate) | **Complete — 2026-08-11** | None |
| P1 | z-score + rolling-SD baseline for HRV(log)/RHR/sleep; ACWR replaces load bonus | Open | None |
| P1 | Volume-weighted per-muscle decay recovery model | Open | None (needs a muscle-contribution table — content work) |
| P2 | Volume landmarks (MEV/MAV/MRV) into `nextWorkout` | Open | None |
| P2 | Deload/plateau detection | Open | None |
| P2 | e1RM ensemble + confidence band; rep-range exclusion | Open | None (RPE/RIR field = `Models.swift` schema bump) |
| P3 | Training monotony/strain | Open | None |
| P3 | Sleep debt | Open | None |
| P3 | HRV-guided standalone flag | Open | None |
| P3 | Weight trend smoothing | Open | None |
| New permission | Respiratory rate / SpO2 / `HKWorkout` corroboration | Open | `respiratoryRate`, `oxygenSaturation`, `HKWorkoutType` |

Everything in P0–P2 uses HealthKit types the app already requests (sleep, HRV
SDNN, resting HR, body mass) plus existing `Workout`/`ExerciseSet` data — no new
permission prompts, all on-device. Any `DailyRecovery`/`ExerciseSet` schema
change (RPE, HRV sample count) should go through the versioned
`AppSchemaV1`→`AppSchemaV2` + migration stage pattern in `DataLifecycle.swift`,
not by editing `Models.swift` in place; calc changes get tests in
`TrainingEngineTests.swift`.

#### Framing & privacy notes
- Frame every score as a wellness/training-load trend indicator, not a diagnostic claim (avoid "overtraining syndrome," "injury risk").
- Keep computation on-device; `AIInsightService` should continue to send only derived summary numbers to the proxy, never raw per-sample HRV/sleep data.
- Nothing proposed adds regulatory exposure; re-review authorization copy if respiratory rate/SpO2 are ever added.

---

## 4. Addendum — logging corrections & reference (2026-08-13)

Two requested features, scoped. Neither needs a schema change, a new HealthKit
type, or a third-party dependency. Priority was set as: **4.1 is P0**
(data-correctness / trust), **4.2 is the top of the P1 logging queue**.

### 4.1 Edit and delete logged workouts — **P0** — *shipped 2026-08-13*

**Why P0.** Every logged workout was write-once. `WorkoutLoggerView` was a
one-shot sheet, `WorkoutDetailView` was read-only, and `WorkoutHistoryView` had
no `.onDelete` or swipe actions — routines had create/edit/delete
(`RoutinesView.swift:75`) but workouts didn't. So a single fat-fingered `500`
instead of `50`:

- becomes a permanent PR that suppresses every future PR on that lift,
- inflates the estimated-1RM trend and the Dashboard strength series,
- corrupts weekly volume, the readiness load term, and muscle recovery,
- and ships into the `AIInsightService` proxy payload as fact.

The engine-side PR sanity guard (§3.2, complete) rejects implausible *jumps* but
cannot undo a bad row, and the only existing escape hatch is "delete all local
data" in Settings — losing all history to fix one set. This is the same trust
class as the completed P0 items in §2 and should land before further P1 work.

**Scope**
- **Delete a workout** from `WorkoutHistoryView` via `.onDelete` / swipe action,
  plus a destructive action in `WorkoutDetailView`. Confirm before deleting
  (`.confirmationDialog`) — this is unrecoverable, there is no undo or trash.
  `Workout` → `ExerciseSet` is already a cascade relationship, so deleting the
  workout removes its sets; verify no orphaned `ExerciseSet` rows remain.
- **Edit a workout** — reuse `WorkoutLoggerView` in an "edit existing" mode
  rather than building a second editor: load the workout's title, date, and sets
  into the existing `LoggedExercise`/`EditableSet` drafts, and on save diff
  against the stored sets instead of inserting a new `Workout`. Editable fields:
  title, date, per-set weight/reps, add/remove sets, add/remove exercises.
  `durationMinutes` stays as captured (`WorkoutTimerEngine`) — offer it as an
  editable field only if it's cheap; don't recompute it from a new `.now`.
- **Re-derivation.** Everything downstream (PRs, e1RM, volume, recovery,
  readiness load) is computed on read by the pure engines in
  `TrainingEngines.swift`, so an edit or delete should propagate with no cached
  state to invalidate. Confirm that assumption holds — any place that snapshots a
  derived value needs invalidating too.
- **Import parity.** Strong-imported workouts are ordinary `Workout` rows, so
  they get the same edit/delete affordances for free.

**Non-goals for the first pass:** undo/restore, edit history/audit trail,
bulk-edit, and editing `normalizedExercise` (changing an exercise's identity
re-buckets it across every analytic — treat as remove-and-re-add instead).

**Risks**
- Deleting the workout that established a PR silently changes historical PR
  copy — acceptable and correct, but worth a line in `FEATURES.md`.
- Editing a set that a previous session's "previous set" reference (§4.2) pointed
  at changes that reference retroactively. Also correct; no mitigation needed.
- **Saving an edit renumbers `setNumber` to restart at 1 per exercise block**
  (the logger's contract), while `SeedData` and Strong imports number sets
  continuously across the session. `StrongImportView.isDuplicate`
  (`StrongImportView.swift:137-146`) sorts stored sets by `setNumber` and zips
  them against the imported order, so re-importing the source CSV may no longer
  dedupe against an edited workout and can create a duplicate. Accepted: the
  affected case is edit-then-reimport-the-same-file, and the alternative is
  persisting intra-workout ordering, which this slice explicitly avoids.
- **Two same-name exercise blocks in one workout merge into one on edit.**
  `ExerciseSet` stores no intra-workout ordering, so nothing says which `1`
  starts which block. Every set, weight, and rep survives — only the split is
  lost, and no analytic reads `setNumber`.

**Tests** (`WorkoutEditingTests.swift`, shipped): `WorkoutEditorLogicTests`
covers the pure prefill/diff logic (groups by raw `exercise` not
`normalizedExercise`, orders by `setNumber`, wires `existingModel` identity,
merges duplicate blocks); `WorkoutEditingPersistenceTests` uses an in-memory
container for deleting a workout cascading its sets, a sibling workout being
unaffected, deleting the PR-setting workout promoting the next-best lift,
editing a set's weight changing `Workout.volume` and the recomputed estimated
1RM, editing down a typo'd 500 kg set removing the bogus PR, and
`calories`/`notes`/`durationMinutes` surviving an edit.

### 4.2 Previous-set reference in the logger — **P1** — *shipped 2026-08-15*

This is the "previous set" clause of P1 item 4 and the "Previous-set reference" /
"'Last time' reference in the logger" entries in the UI review (§3.1). It ships
independently of the rest timer and `WorkoutInProgress` persistence, which remain
part of the larger deferred item 4.

**Implemented**
- `ExerciseLoggerCard` shows the most recent prior performance under the exercise
  header, including relative age, with references older than eight weeks dimmed.
- Lookup excludes the workout being edited, matches normalized exercise names, and
  orders sets by `setNumber` with deterministic tie-breakers.
- Each current set row shows a dim reference to the corresponding prior set when
  one exists; first-time exercises show no placeholder.
- Routine-prefilled targets remain unchanged; manually added exercises initialize
  editable draft sets from the corresponding sets in the most recent performance.
- Added focused `PreviousSetTests` coverage for recency, aliases, edit exclusion,
  first-time exercises, ordering, equal-date determinism, and draft prefill.

**Deferred**
- Rest timer, running volume, and `WorkoutInProgress` persistence remain part of
  the original item 4.

**Scope**
- In `ExerciseLoggerCard` (`WorkoutLoggerView.swift:140`), show the most recent
  prior performance for that exercise as secondary text under the header — e.g.
  `Last: 60 × 8, 60 × 8, 62.5 × 6 · 12 days ago`.
- **Lookup:** most recent `Workout` (excluding the in-progress one) containing an
  `ExerciseSet` whose `normalizedExercise` matches the drafted exercise; take
  that workout's sets for the exercise in `setNumber` order. Normalization
  already exists via `ExerciseCatalog.normalize`, so "Bench Press" and "Barbell
  Bench Press" resolve together.
- **Per-set inline hint** (secondary): dim placeholder on each set row showing
  the matching set number from last time, so set 3 shows what set 3 was.
- **Empty state:** first time doing an exercise → "First time logging this" or
  no row at all; never render a `0 × 0` placeholder.
- **Staleness:** show relative age; consider de-emphasizing references older
  than ~8 weeks rather than hiding them.
- **Prefill:** when an exercise is manually added, initialize its editable sets
  from the corresponding sets in the most recent prior performance. The values
  remain editable; routine targets remain authoritative, and editing an existing
  workout preserves its stored draft values.
- **Routine interaction:** when starting from a routine, the routine's target
  sets/reps/weight already prefill the draft — show the previous-set reference
  *alongside* the target, not instead of it, so target vs. actual stay distinct.

**Performance:** one lookup per drafted exercise, over `@Query`-loaded workouts
sorted by date descending — cheap at personal-history scale. If the logger's
exercise list grows long, resolve all references in a single pass over recent
workouts rather than per-card queries.

**Tests** (`TrainingEngineTests.swift` or a focused `PreviousSetTests.swift`):
picks the most recent prior workout, not the highest-volume one; matches across
name variants via `normalizedExercise`; excludes the in-progress workout;
returns nil for a first-time exercise; orders sets by `setNumber`.

### 4.3 Sequencing

1. ~~**4.1 delete**~~ / ~~**4.1 edit**~~ — shipped together on 2026-08-13 rather
   than as two slices: they share the confirmation and navigation plumbing, and
   delete alone still leaves "lose the whole session to fix one set".
2. **4.2 previous-set reference + editable prefill** — shipped independently of
   4.1; it shows the prior performance and initializes manually added exercises
   from it without overriding routine targets or edit drafts.

Deferred to the original item 4: rest timer, running volume, and
`WorkoutInProgress` persistence.
