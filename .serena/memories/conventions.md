---
name: conventions
description: Code organization and implementation rules specific to this Swift codebase.
---
- Four-space indentation; UpperCamelCase types; lowerCamelCase members; prefer `let` and native APIs.
- Keep reusable, persistence-free domain logic in stateless engines in `TrainingEngines.swift`; add focused XCTest coverage for non-trivial calculations/parsing.
- SwiftData models are versioned through `DataLifecycle.swift` migrations; update app schema registration and `CLAUDE.md` current-version note together.
- UI ownership: `RootView.swift` for navigation/home/dashboard/history/detail; `WorkoutLoggerView.swift` for logging/editing/routines-as-entry/drafts/timer/RPE/set types; `RoutinesView.swift` for routines; `RecoveryAndCoachViews.swift` for recovery/coach; shared components only when actually reused.
- HealthKit is read-only; AI coaching is proxy-only with local recommendation fallback, never provider keys in app.
- Treat readiness/recovery/recommendations as training/wellness guidance, not medical diagnosis; distinguish missing data from zero.
- User-visible changes update `FEATURES.md`; roadmap completion and current focus update `SPEC.md`.