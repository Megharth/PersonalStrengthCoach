---
name: tech_stack
description: Stable platform, framework, and dependency constraints.
---
- SwiftUI, SwiftData, HealthKit, Charts, UniformTypeIdentifiers, Foundation; Apple frameworks only.
- Deployment target: iOS 18 or later; development requires macOS with Xcode 16+.
- No package manager or third-party dependencies.
- Single app `ModelContainer` is initialized from `Schema(AppSchemaV5.models)` and `AppMigrationPlan`.
- Debug builds seed sample data through `SeedData.swift`; release builds expose only device data.