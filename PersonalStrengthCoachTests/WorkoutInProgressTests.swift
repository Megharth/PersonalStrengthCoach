import SwiftData
import XCTest
@testable import PersonalStrengthCoach

final class WorkoutInProgressTests: XCTestCase {
    func testVolumeCountsCompletedSetsOnly() {
        let exercise = LoggedExercise(name: "Bench Press", primaryMuscle: .chest, sets: [
            EditableSet(weight: 100, reps: 5, isCompleted: true),
            EditableSet(weight: 100, reps: 5)
        ])

        XCTAssertEqual(WorkoutInProgressEngine.volume(of: [exercise]), 500, accuracy: 0.001)
    }

    func testRestCountdownHandlesMissingAndExpiredTimers() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertNil(WorkoutInProgressEngine.remainingRestSeconds(endsAt: nil, now: now))
        XCTAssertEqual(WorkoutInProgressEngine.remainingRestSeconds(endsAt: now.addingTimeInterval(2.2), now: now), 3)
        XCTAssertEqual(WorkoutInProgressEngine.remainingRestSeconds(endsAt: now.addingTimeInterval(-1), now: now), 0)
    }

    func testDraftRoundTripPreservesExerciseOrderSetOrderAndCompletion() {
        let exercises = [
            LoggedExercise(name: "Squat", primaryMuscle: .quads, sets: [
                EditableSet(weight: 140, reps: 5, isCompleted: true),
                EditableSet(weight: 140, reps: 5)
            ]),
            LoggedExercise(name: "Bench Press", primaryMuscle: .chest, sets: [
                EditableSet(weight: 80, reps: 8, isCompleted: true)
            ])
        ]

        let persisted = WorkoutInProgressEngine.persistedSets(from: exercises)
        let restored = WorkoutInProgressEngine.draftExercises(from: persisted)

        XCTAssertEqual(restored.map(\.name), ["Squat", "Bench Press"])
        XCTAssertEqual(restored[0].sets.map(\.weight), [140, 140])
        XCTAssertEqual(restored[0].sets.map(\.reps), [5, 5])
        XCTAssertEqual(restored[0].sets.map(\.isCompleted), [true, false])
        XCTAssertEqual(restored[1].sets.map(\.isCompleted), [true])
    }

    func testElapsedSecondsClampsFutureClockToZero() {
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(WorkoutInProgressEngine.elapsedSeconds(start: start, now: start.addingTimeInterval(-1)), 0)
        XCTAssertEqual(WorkoutInProgressEngine.elapsedSeconds(start: start, now: start.addingTimeInterval(61)), 61)
    }

    func testResolveActiveSessionPicksNewestAndReturnsStrays() {
        let older = WorkoutInProgress(lastUpdated: Date(timeIntervalSince1970: 100))
        let newest = WorkoutInProgress(lastUpdated: Date(timeIntervalSince1970: 300))
        let middle = WorkoutInProgress(lastUpdated: Date(timeIntervalSince1970: 200))

        let resolved = WorkoutInProgressEngine.resolveActiveSession(among: [older, newest, middle])

        XCTAssertTrue(resolved.current === newest)
        XCTAssertEqual(resolved.strays.count, 2)
        XCTAssertTrue(resolved.strays.contains { $0 === older })
        XCTAssertTrue(resolved.strays.contains { $0 === middle })
    }

    func testResolveActiveSessionReturnsNilForEmptyInput() {
        let resolved = WorkoutInProgressEngine.resolveActiveSession(among: [])

        XCTAssertNil(resolved.current)
        XCTAssertTrue(resolved.strays.isEmpty)
    }
}

final class WorkoutInProgressPersistenceTests: XCTestCase {
    private func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(AppSchemaV4.models),
            migrationPlan: AppMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    func testDraftMetadataTimerAndSetsPersistAndReload() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let sessionStart = Date(timeIntervalSince1970: 1_000)
        let updated = Date(timeIntervalSince1970: 1_200)
        let session = WorkoutInProgress(
            title: "Push Day",
            date: Date(timeIntervalSince1970: 900),
            sessionStart: sessionStart,
            lastUpdated: updated
        )
        session.restStartedAt = Date(timeIntervalSince1970: 1_100)
        session.restEndsAt = Date(timeIntervalSince1970: 1_190)
        let completed = WorkoutInProgressSet(
            exercise: "Bench Press",
            primaryMuscle: .chest,
            exerciseOrder: 0,
            weight: 80,
            reps: 8,
            setNumber: 1,
            isCompleted: true
        )
        let unfinished = WorkoutInProgressSet(
            exercise: "Bench Press",
            primaryMuscle: .chest,
            exerciseOrder: 0,
            weight: 80,
            reps: 8,
            setNumber: 2
        )
        completed.session = session
        unfinished.session = session
        session.sets = [completed, unfinished]
        context.insert(session)
        try context.save()

        let reloaded = try context.fetch(FetchDescriptor<WorkoutInProgress>()).first!
        XCTAssertEqual(reloaded.title, "Push Day")
        XCTAssertEqual(reloaded.sessionStart, sessionStart)
        XCTAssertEqual(reloaded.restStartedAt, Date(timeIntervalSince1970: 1_100))
        XCTAssertEqual(reloaded.restEndsAt, Date(timeIntervalSince1970: 1_190))
        let sets = reloaded.sets.sorted { $0.setNumber < $1.setNumber }
        XCTAssertEqual(sets.map(\.weight), [80, 80])
        XCTAssertEqual(sets.map(\.isCompleted), [true, false])
    }

    func testDeletingDraftCascadesToItsSets() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let session = WorkoutInProgress()
        let set = WorkoutInProgressSet(
            exercise: "Squat",
            primaryMuscle: .quads,
            exerciseOrder: 0,
            weight: 100,
            reps: 5,
            setNumber: 1
        )
        set.session = session
        session.sets = [set]
        context.insert(session)
        try context.save()

        context.delete(session)
        try context.save()

        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutInProgress>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutInProgressSet>()).isEmpty)
    }

    func testPruningStrayDraftsLeavesNewestSessionAndChildren() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let older = WorkoutInProgress(title: "Old", lastUpdated: Date(timeIntervalSince1970: 100))
        let newest = WorkoutInProgress(title: "Newest", lastUpdated: Date(timeIntervalSince1970: 200))
        for session in [older, newest] { context.insert(session) }
        try context.save()

        let resolved = WorkoutInProgressEngine.resolveActiveSession(among: [older, newest])
        resolved.strays.forEach(context.delete)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<WorkoutInProgress>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.title, "Newest")
    }

    func testCurrentSchemaContainsDraftModelsAndBuildsContainer() throws {
        XCTAssertTrue(AppSchemaV4.models.contains { $0 == WorkoutInProgress.self })
        XCTAssertTrue(AppSchemaV4.models.contains { $0 == WorkoutInProgressSet.self })
        _ = try makeInMemoryContainer()
    }
}
