# Repository Guidelines

## Project Structure & Module Organization

`PersonalStrengthCoach/` contains the SwiftUI application. `PersonalStrengthCoachApp.swift` configures the app and SwiftData container; `RootView.swift` owns the main navigation. Keep persistent models and exercise metadata in `Models.swift`, calculation logic in `TrainingEngines.swift`, and reusable UI in `Components.swift`. Feature screens use descriptive filenames such as `WorkoutLoggerView.swift` and `StrongImportView.swift`. App icons and asset metadata live in `PersonalStrengthCoach/Assets.xcassets/`. Xcode project settings and the shared scheme are under `PersonalStrengthCoach.xcodeproj/`.

## Build, Test, and Development Commands

- `open PersonalStrengthCoach.xcodeproj` opens the project in Xcode. Select an iOS 18 simulator and press `Command-R` to run.
- `xcodebuild -project PersonalStrengthCoach.xcodeproj -scheme PersonalStrengthCoach -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build` performs a reproducible command-line build without signing.
- `xcodebuild -project PersonalStrengthCoach.xcodeproj -scheme PersonalStrengthCoach clean` removes Xcode build products.

The app uses Apple frameworks only, so there is no package-install step.

## Coding Style & Naming Conventions

Follow standard Swift conventions and the existing four-space indentation. Use `UpperCamelCase` for types, `lowerCamelCase` for properties and functions, and names that describe intent. Keep SwiftUI views small enough to scan; extract shared visual elements into `Components.swift` only when reused. Prefer immutable `let` values and native SwiftUI, SwiftData, Charts, and Foundation APIs. No formatter or linter is currently configured; use Xcode's indentation and warnings as the baseline.

## Testing Guidelines

There is currently no XCTest target or coverage requirement. Before submitting changes, run the command-line build and exercise the affected flow in an iOS 18 simulator. For non-trivial parsing or calculation changes, add an XCTest target and focused tests named `<Feature>Tests.swift`, with methods such as `testStrongImportRejectsInvalidRows()`.

## Commit & Pull Request Guidelines

The repository has no commit history from which to infer a convention. Use short, imperative commit subjects, for example `Fix readiness score calculation`. Keep each commit focused. Pull requests should explain the user-visible change, list verification performed, and link any related issue. Include simulator screenshots or recordings for UI changes. Never commit API keys, Health data, derived build output, or user-specific Xcode state.
