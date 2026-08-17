# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users

The primary user is a solo lifter tracking their own strength training and recovery.

## Product Purpose

Personal Strength Coach is an iOS strength-training tracker that keeps workout and recovery records on-device, imports relevant Apple Health data, and turns the history into progress trends, personal records, readiness scores, and next-workout suggestions. Success means the user can log training reliably, understand whether their strength is progressing, and make better day-to-day training decisions from their own data.

## Positioning

Progress analytics are the product's core difference from a generic workout logger: the app should make strength progression, personal records, and trends unusually clear over time, while using readiness and recovery data to add context to those trends.

## Operating Context

The user logs workouts during or after gym sessions, often on an iPhone. They may start from a saved routine, continue an interrupted session, import an existing Strong history, or review trends between workouts. Apple Health supplies read-only sleep, HRV, resting-heart-rate, and body-mass data when available. The user may enter and view lifting weights in kilograms or pounds; persisted calculations remain canonical kilograms.

## Capabilities and Constraints

- SwiftUI + SwiftData iOS app using Apple frameworks only; no third-party package dependencies.
- Logs workouts, exercises, sets, set types, optional RPE, duration, routines, custom exercises, and resumable in-progress sessions.
- Derives volume, estimated 1RM, personal records, readiness, muscle recovery, and workout recommendations through on-device pure engines.
- Supports Strong CSV, JSON, and shared-workout text imports, plus JSON export and deletion of local data.
- Apple Health integration is read-only and currently covers sleep, HRV, resting heart rate, and body mass.
- Optional AI coaching uses a proxy and must retain a local fallback; the app does not contain a provider key or call a provider directly.
- SwiftData model changes require a new versioned schema and migration stage. Derived build output and user-specific Xcode state remain local and untracked.
- Scores and recommendations are wellness/training indicators, not medical or diagnostic claims.

## Brand Commitments

The product name is Personal Strength Coach. Existing product documentation describes a practical, evidence-aware, privacy-conscious training companion. Preserve honest presentation of calculated data and distinguish missing or low-confidence data from a measured zero.

## Evidence on Hand

- The implemented product and focused XCTest suites in this repository are the primary evidence of current capabilities.
- `SPEC.md` is the authoritative roadmap and current-focus record.
- `FEATURES.md` documents user-visible behavior.
- No testimonials, customer claims, or external performance benchmarks are provided; future work must not fabricate them.

## Product Principles

1. Show the user's real history honestly; never substitute fabricated or placeholder metrics for missing data.
2. Make progress legible: connect sets and sessions to trends, records, and actionable context.
3. Keep logging fast and resilient enough for real gym conditions, including interruptions and imperfect input.
4. Keep personal training and health data private by default through on-device storage and read-only HealthKit access.
5. Frame derived scores as useful training guidance with appropriate confidence, not medical certainty.

## Accessibility & Inclusion

The app should follow native iOS accessibility expectations: Dynamic Type, VoiceOver labels and chart descriptions, minimum 44-point touch targets, semantic system colors, Dark Mode, and Reduce Motion support. No more specific user need or compliance standard has been established.
