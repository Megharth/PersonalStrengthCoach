# Personal Strength Coach

An iOS strength-training tracker built with SwiftUI and SwiftData. It keeps workout and recovery data on-device, then turns it into readiness scores, progress trends, personal records, and next-workout suggestions.

## Features

- Log workouts, exercises, sets, weight, and reps; newly added exercises prefill editable sets from recent history
- Use the built-in exercise library or add custom exercises
- Import Strong exports from CSV, JSON, or shared-workout text
- Track volume, estimated one-rep max, and personal records
- View sleep, HRV, resting-heart-rate, and muscle-recovery trends
- Import sleep, HRV, resting heart rate, and body mass from Apple Health
- Get local readiness scores and workout recommendations
- Explore debug builds immediately with automatically generated sample data

## Requirements

- macOS with Xcode 16 or later
- iOS 18 or later

The project uses only Apple frameworks: SwiftUI, SwiftData, Charts, and Uniform Type Identifiers. No package installation is required.

## Run

1. Clone or download the repository.
2. Open `PersonalStrengthCoach.xcodeproj` in Xcode.
3. Select an iOS 18 simulator or connected device.
4. Press **Run** (`⌘R`).

## Using the app

Open **History**, tap **+**, and choose **Log workout** to record a session. From the same menu, choose **Import from Strong** to select or paste an export. The Today, Dashboard, Recovery, and Coach tabs update from the saved data.

All workout and recovery records are stored locally with SwiftData. Apple Health access is read-only.
Sample data is added only in debug builds; release builds show data saved on the device.

The Settings tab exports local workouts, recovery records, and custom exercises as versioned JSON and can delete the local SwiftData store. Deleting app data does not delete Apple Health history. SwiftData models are registered through `AppMigrationPlan`; future model changes should add a new versioned schema and migration stage.

## Project structure

The source is organized by data models and lifecycle (`Models.swift`,
`DataLifecycle.swift`), pure calculations (`TrainingEngines.swift`), domain UI
(`RootView.swift`, `WorkoutLoggerView.swift`, `RoutinesView.swift`, and
`RecoveryAndCoachViews.swift`), HealthKit/import/AI services, and focused XCTest
suites. The maintained file-to-feature routing map, current schema version, and
feature-shipping checklist live in `CLAUDE.md`; use it instead of maintaining a
second file list here. Run `Scripts/check-doc-freshness.sh` to detect drift in
that map.

The roadmap and current next item live in `SPEC.md`. User-visible behavior is
documented in `FEATURES.md`.

## Documentation workflow

For a fresh feature-planning session, use the project-local `/next-feature`
command. It reads the current-focus pointer, validates the implementation map,
and narrows source inspection to the selected feature instead of repeating a
full repository survey.


## Coach integration status

Coach AI calls the configured `AIProxyURL`; the app never contains an OpenAI key or calls the provider directly. The proxy must authenticate the app, rate-limit requests, redact sensitive data, call OpenAI server-side, and return `{ "text": "..." }`. Configure `AI_PROXY_URL` per Release environment; when it is absent or unavailable, the app uses the local recommendation.
