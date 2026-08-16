# Plan the next feature

Use this command before planning or implementing the next item from `SPEC.md`.

## Automatic preflight

1. Read `SPEC.md`'s `## Current focus` section and Section 2. Treat these as the
   authoritative roadmap/status. Do not scan historical review prose to decide
   what is next.
2. Read `CLAUDE.md`'s **Layer and file map**, **Where to look first**, and
   **Shipping a spec item** sections. These are the maintained implementation
   map and workflow.
3. Read only the relevant rationale in `SPEC.md` Sections 3 and 4. Treat every
   file/line citation there as a historical hint, not current fact.
4. Before trusting the map, run the repository freshness check when available:

   ```bash
   Scripts/check-doc-freshness.sh
   ```

   If it fails, reconcile `CLAUDE.md` with the source before making the feature
   plan. At minimum, spot-check the highest `AppSchemaVN` in
   `PersonalStrengthCoach/DataLifecycle.swift` and the `*Engine` declarations
   in `PersonalStrengthCoach/TrainingEngines.swift`.
5. Inspect only the selected feature's affected source, persistence,
   import/export, UI, and focused test files from the `CLAUDE.md` routing table.
   Do not repeat a whole-repository survey unless the freshness check or the
   selected feature reveals a missing ownership entry.

## During implementation

Follow `CLAUDE.md`'s **Shipping a spec item** checklist. Keep `handoff.md`
current during implementation and remove it only after the build and tests pass.
Update `SPEC.md` status/current focus in the same commit as the feature, and
update `FEATURES.md` only when user-visible behavior changes.

## Why this is automatic

The command turns the repeated fresh-thread reconnaissance into a fixed,
project-local preflight. The freshness script catches structural drift, while
`CLAUDE.md` remains the human-readable implementation map and `SPEC.md` remains
the product-status source of truth. No separate feature manifest is maintained.
