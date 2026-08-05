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
```

There is no linter/formatter configured; follow Xcode's warnings and the conventions below.

## Architecture

- **Data layer**: SwiftData models live in `Models.swift` (`Workout` → `ExerciseSet` cascade relationship, `DailyRecovery`, `CustomExercise`) plus `ExerciseCatalog`/`ExerciseLibrary` (exercise name normalization, muscle-group inference, seeded exercise list). Schema versioning and migrations live in `DataLifecycle.swift` as `AppSchemaV1`/`AppMigrationPlan` — bump this (new versioned schema + migration stage) whenever a model changes shape, don't just edit `Models.swift` in place. `DataLifecycle.swift` also owns JSON export (`PersonalStrengthExport`) and the "delete all local data" flow, both driven from `DataManagementView` (Settings tab).
- **Calculation layer** (`TrainingEngines.swift`): pure, stateless enums — `RecoveryEngine` (readiness score, muscle recovery %), `PerformanceEngine` (weekly volume, estimated 1RM, PR detection), `RecommendationEngine` (next-workout suggestion). These take model instances/arrays as plain arguments and return value types, which is why they're easy to unit test without a SwiftData container (see `TrainingEngineTests.swift`).
- **HealthKit sync** (`HealthKitService.swift`): read-only, `@MainActor` enum. Pulls the last 15 days of sleep/HRV/resting-HR/body-mass and upserts into `DailyRecovery` rows. Sleep is attributed to the day it *ends* (wake-up day), with overlapping sleep-analysis intervals merged before summing.
- **AI coaching** (`AIInsightService.swift`): proxy-only client — the app never holds an OpenAI key or calls the provider directly. It POSTs to `AIProxyURL` (from Info.plist, configured per-environment via `AI_PROXY_URL`) and expects back `{ "text": "..." }`. If the key is absent/unset, the caller falls back to the local `RecommendationEngine` result — preserve that fallback when touching this path.
- **Import** (`StrongImportView.swift`): parses Strong app exports (CSV, JSON, or shared-workout text) into `Workout`/`ExerciseSet` models, including bodyweight-set handling.
- **UI**: `RootView.swift` owns tab navigation, dashboard, and history; `WorkoutLoggerView.swift` is workout/custom-exercise logging; `RecoveryAndCoachViews.swift` covers recovery trends and the coach screen; `Components.swift` holds shared cards/charts (only put something here once it's actually reused — see conventions).
- **Entry point**: `PersonalStrengthCoachApp.swift` builds the single `ModelContainer` from `AppSchemaV1`/`AppMigrationPlan` and forces dark mode.
- Debug builds seed sample data via `SeedData.swift`; release builds only show real device data.

## Conventions

- Four-space indentation, `UpperCamelCase` types, `lowerCamelCase` members, descriptive names.
- Prefer `let` and native SwiftUI/SwiftData/Charts/Foundation APIs over introducing anything new.
- Extract to `Components.swift` only when a view is actually reused elsewhere — don't pre-factor.
- For non-trivial parsing or calculation changes, add/extend focused XCTests named `<Feature>Tests.swift` (e.g. `testStrongImportRejectsInvalidRows()`), following the pattern in `StrongImportParserTests.swift` / `TrainingEngineTests.swift`.
- Never commit API keys, Health data, derived build output (`.build/`), or user-specific Xcode state.
- Exercise `.build/` and `.codex/` should stay untracked; they hold local build products and tooling state, not source.
