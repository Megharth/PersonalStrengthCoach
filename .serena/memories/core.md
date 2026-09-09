---
name: core
description: Project map and invariants for the Personal Strength Coach iOS app.
---
- iOS strength tracker; SwiftUI + SwiftData, Apple frameworks only, on-device records.
- Source map: models/schema/export in `Models.swift` + `DataLifecycle.swift`; pure calculations in `TrainingEngines.swift`; app entry in `PersonalStrengthCoachApp.swift`; primary UI in `RootView.swift`, `WorkoutLoggerView.swift`, `RoutinesView.swift`, `RecoveryAndCoachViews.swift`; imports in `StrongImportView.swift`; HealthKit in `HealthKitService.swift`/`HealthKitValidation.swift`.
- Current SwiftData schema is AppSchemaV5. Model shape changes require a new versioned schema and migration stage; never edit an existing snapshot in place.
- Persisted weights and calculation inputs are canonical kilograms; unit presentation/entry is centralized in `WeightUnit`.
- `SPEC.md` current-focus pointer and Section 2 are authoritative roadmap; currently next is completion of per-exercise progress analytics.
- Read `mem:tech_stack` for platform/build details; `mem:conventions` for architecture/style; `mem:suggested_commands` and `mem:task_completion` for verification commands.