#!/bin/sh

set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
claude_file="$root_dir/CLAUDE.md"
schema_file="$root_dir/PersonalStrengthCoach/DataLifecycle.swift"
engines_file="$root_dir/PersonalStrengthCoach/TrainingEngines.swift"

failures=0

fail() {
    printf '%s\n' "check-doc-freshness: $*" >&2
    failures=$((failures + 1))
}

if [ ! -f "$claude_file" ]; then
    fail "missing CLAUDE.md"
fi
if [ ! -f "$schema_file" ]; then
    fail "missing $schema_file"
fi
if [ ! -f "$engines_file" ]; then
    fail "missing $engines_file"
fi

if [ "$failures" -eq 0 ]; then
    schema_version=$(grep -Eo 'AppSchemaV[0-9]+' "$schema_file" | sed 's/[^0-9]//g' | sort -n | tail -1)
    if [ -z "$schema_version" ]; then
        fail "could not find an AppSchemaV<number> declaration in DataLifecycle.swift"
    elif ! grep -Fq "Current: \`AppSchemaV${schema_version}\`" "$claude_file"; then
        fail "CLAUDE.md does not document Current: AppSchemaV${schema_version}"
    fi

    engine_names=$(grep -E '^enum[[:space:]]+[A-Za-z0-9_]+Engine([[:space:]]|\{|$)' "$engines_file" \
        | sed -E 's/^enum[[:space:]]+([A-Za-z0-9_]+Engine).*/\1/' \
        | sort -u)
    for engine in $engine_names; do
        if ! grep -Fq "\`$engine\`" "$claude_file"; then
            fail "CLAUDE.md does not document $engine"
        fi
    done

    for file in \
        Models.swift \
        DataLifecycle.swift \
        PersonalStrengthCoachApp.swift \
        TrainingEngines.swift \
        WorkoutLoggerView.swift \
        RoutinesView.swift \
        RootView.swift \
        RecoveryAndCoachViews.swift \
        HealthKitService.swift \
        HealthKitValidation.swift \
        StrongImportView.swift \
        AIInsightService.swift \
        Components.swift \
        SeedData.swift; do
        if ! grep -Fq "\`$file\`" "$claude_file"; then
            fail "CLAUDE.md does not document expected source file $file"
        fi
    done
fi

if [ "$failures" -ne 0 ]; then
    printf '%s\n' "check-doc-freshness: $failures check(s) failed" >&2
    exit 1
fi

printf '%s\n' "check-doc-freshness: CLAUDE.md matches the current schema, engines, and source-file map"
