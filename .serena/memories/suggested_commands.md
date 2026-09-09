---
name: suggested_commands
description: Project-specific commands for opening, building, testing, and documentation checks on macOS.
---
- Open project: `open PersonalStrengthCoach.xcodeproj`.
- Unsigned build: `xcodebuild -project PersonalStrengthCoach.xcodeproj -scheme PersonalStrengthCoach -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build`.
- Simulator tests: `xcodebuild -project PersonalStrengthCoach.xcodeproj -scheme PersonalStrengthCoach -destination 'platform=iOS Simulator,name=iPhone 16' test`.
- Focused XCTest: append `-only-testing:PersonalStrengthCoachTests/<Suite>/<testMethod>` before `test`.
- Documentation freshness: `Scripts/check-doc-freshness.sh`.
- Open the Xcode project with macOS `open`; no install/package command is needed.