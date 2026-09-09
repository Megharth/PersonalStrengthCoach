---
name: task_completion
description: Verification checklist for shipping a code change in this repository.
---
- Run focused XCTest coverage for changed pure logic, parser, model, or persistence behavior.
- Run the full documented simulator XCTest command when feasible, plus the unsigned generic iOS build.
- Run `Scripts/check-doc-freshness.sh` when source ownership/schema/version/docs changed.
- Before declaring a spec item complete: update `SPEC.md` current focus/status and `FEATURES.md` for user-visible behavior; update `CLAUDE.md` if schema/engine/file ownership changed.
- Do not claim completion if build/tests fail or verification was skipped; preserve a root `handoff.md` while implementation or verification remains incomplete.