# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Personal Strength Coach: an iOS strength-training tracker (SwiftUI + SwiftData). Logs workouts and recovery data on-device, then derives readiness scores, PRs, and next-workout suggestions. Apple frameworks only (SwiftUI, SwiftData, HealthKit, Charts, UniformTypeIdentifiers) — no package manager, no third-party dependencies.

## Build, test, run

```bash
# Open in Xcode (iOS 18 simulator, Cmd-R)
open PersonalStrengthCoach.xcodeproj

# Command-line build, no signing
xcodebuild -project PersonalStrengthCoach.xcodeproj -scheme PersonalStrengthCoach \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build

# Clean
xcodebuild -project PersonalStrengthCoach.xcodeproj -scheme PersonalStrengthCoach clean

# Run tests (XCTest target: PersonalStrengthCoachTests) on a simulator
xcodebuild -project PersonalStrengthCoach.xcodeproj -scheme PersonalStrengthCoach \
  -destination 'platform=iOS Simulator,name=iPhone 16' test

# Run a single test
xcodebuild -project PersonalStrengthCoach.xcodeproj -scheme PersonalStrengthCoach \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PersonalStrengthCoachTests/StrongImportParserTests/testMethodName test

# Run the automated UI suite (override DESTINATION or pass -only-testing as needed)
Scripts/run-ui-tests.sh
Scripts/run-ui-tests.sh -only-testing:PersonalStrengthCoachUITests/NavigationUITests
```

UI tests launch the app with `-ui-testing` and an optional `-ui-test-scenario` (`empty`, `history`, or `recovery`). They use an in-memory SwiftData store and fixed fixtures, and bypass HealthKit synchronization so runs do not require permissions, network access, or manual simulator interaction. Results are written to `.build/ui-tests.xcresult` by default.

There is no linter/formatter configured; follow Xcode's warnings and the conventions below.

## Architecture

### Layer and file map

- **Data layer**: SwiftData models live in `Models.swift` (`Workout` → `ExerciseSet` cascade relationship, `DailyRecovery`, `CustomExercise`, `Routine`, and resumable `WorkoutInProgress` models) plus `ExerciseCatalog`/`ExerciseLibrary` (exercise normalization, muscle-group inference, and seeded exercises). Schema versioning and migrations live in `DataLifecycle.swift` as `AppSchemaV1`…`AppSchemaVN` plus `AppMigrationPlan`. **Current: `AppSchemaV5`.** Add a new versioned schema and migration stage whenever a model changes shape; update this current-version line in the same commit. Do not edit an existing schema snapshot in place. `DataLifecycle.swift` also owns JSON export and delete-all-data, driven from `DataManagementView`.
- **Calculation layer** (`TrainingEngines.swift`): pure, stateless engines — `RPEEngine` (RPE validation/RIR), `RepsEngine` (repetition bounds), `RecoveryEngine` (readiness and muscle recovery), `PerformanceEngine` (volume, estimated 1RM, PRs), `RecommendationEngine` (next workout), `PreviousSetEngine` (prior performance/prefill), `RoutineEngine` (routine drafts), `WorkoutTimerEngine` (duration/rest timing), and `WorkoutInProgressEngine` (draft/session calculations). `WeightUnit` in the same file centralizes kg/lb conversion and presentation formatting; persisted lifting weights and calculation inputs remain canonical kilograms. Prefer this layer for logic that can be expressed without SwiftData or SwiftUI.
- **HealthKit**: `HealthKitService.swift` is a read-only `@MainActor` sync for the last 15 days of sleep, HRV, resting HR, and body mass; `HealthKitValidation.swift` validates physiologic samples and sync states. Sleep is attributed to the day it ends (wake-up day), with overlapping intervals merged before summing.
- **AI coaching** (`AIInsightService.swift`): proxy-only client. The app never holds an OpenAI key or calls the provider directly. It POSTs to `AI_PROXY_URL` and expects `{ "text": "..." }`; when the proxy is absent/unavailable, callers fall back to local `RecommendationEngine` output.
- **Import** (`StrongImportView.swift`): parses Strong CSV, JSON, or shared-workout text into ordinary `Workout`/`ExerciseSet` rows, including bodyweight sets; update `StrongImportParserTests.swift` for parser changes.
- **UI**: `RootView.swift` owns tab navigation, Today, dashboard, history, and workout detail; `WorkoutLoggerView.swift` owns new/edit logging, routines-as-entry, previous-set references, resumable drafts, rest timer, set types, and RPE controls; `RoutinesView.swift` owns routine management; `RecoveryAndCoachViews.swift` owns recovery and coach screens; `Components.swift` holds shared cards/charts only when actually reused.
- **Entry point**: `PersonalStrengthCoachApp.swift` builds the single `ModelContainer` from `Schema(AppSchemaV5.models)` and `AppMigrationPlan`, and forces dark mode.
- Debug builds seed sample data via `SeedData.swift`; release builds only show real device data.

### Where to look first

| Concern | Primary files | Focused tests |
| --- | --- | --- |
| Models, schema, migrations, export/delete | `Models.swift`, `DataLifecycle.swift`, `PersonalStrengthCoachApp.swift` | `WorkoutEditingTests.swift`, `RoutineTests.swift`, `WorkoutInProgressTests.swift` |
| Pure calculations | `TrainingEngines.swift` | `TrainingEngineTests.swift`, `PreviousSetTests.swift`, `WorkoutTimerEngineTests.swift`, `WorkoutInProgressTests.swift` |
| Workout logging/editing/drafts | `WorkoutLoggerView.swift`, `RootView.swift` | `WorkoutEditingTests.swift`, `WorkoutLoggerRoutineDraftTests.swift`, `WorkoutInProgressTests.swift` |
| Routines | `RoutinesView.swift`, `Models.swift`, `TrainingEngines.swift` | `RoutineTests.swift`, `RoutineEditorTests.swift` |
| HealthKit/recovery | `HealthKitService.swift`, `HealthKitValidation.swift`, `RecoveryAndCoachViews.swift` | `HealthKitIngestionTests.swift`, `HealthKitValidationTests.swift`, `TrainingEngineTests.swift` |
| Strong import | `StrongImportView.swift`, `Models.swift` | `StrongImportParserTests.swift` |
| Coach/dashboard/navigation | `AIInsightService.swift`, `RecoveryAndCoachViews.swift`, `RootView.swift`, `Components.swift` | `TrainingEngineTests.swift` |

### Shipping a spec item

1. Read `SPEC.md`'s `## Current focus` and Section 2; do not infer the next item from historical review prose.
2. If model shape changes, add `AppSchemaVN+1` and a migration stage in `DataLifecycle.swift`, update `PersonalStrengthCoachApp.swift`, and update the current schema line above.
3. Put reusable pure logic in `TrainingEngines.swift` and add focused `<Feature>Tests.swift` coverage before or alongside UI wiring.
4. Update every affected persistence, import/export, and UI path using the table above.
5. Mark the item and `## Current focus` in `SPEC.md` in the same commit; bump its last-updated date.
6. Update `FEATURES.md` when user-visible behavior changes; do not use it as an implementation map.
7. Update this file when a schema version, engine, or file ownership changes. Run `Scripts/check-doc-freshness.sh` when present.
8. Run the documented build and XCTest commands before declaring the feature complete.

## Conventions

- Four-space indentation, `UpperCamelCase` types, `lowerCamelCase` members, descriptive names.
- Prefer `let` and native SwiftUI/SwiftData/Charts/Foundation APIs over introducing anything new.
- Extract to `Components.swift` only when a view is actually reused elsewhere — don't pre-factor.
- For non-trivial parsing or calculation changes, add/extend focused XCTests named `<Feature>Tests.swift` (e.g. `testStrongImportRejectsInvalidRows()`), following the pattern in `StrongImportParserTests.swift` / `TrainingEngineTests.swift`.
- Never commit API keys, Health data, derived build output (`.build/`), or user-specific Xcode state.
- Exercise `.build/` and `.codex/` should stay untracked; they hold local build products and tooling state, not source.
