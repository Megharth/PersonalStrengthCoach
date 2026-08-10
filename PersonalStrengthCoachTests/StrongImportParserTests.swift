import XCTest
@testable import PersonalStrengthCoach

final class StrongImportParserTests: XCTestCase {
    func testJSONAcceptsZeroWeightBodyweightSet() throws {
        let result = try StrongImportParser.parse(#"{"workouts":[{"name":"Bodyweight","date":"2025-01-01","exercises":[{"name":"Push Up","sets":[{"weight":0,"reps":10}]}]}]}"#)

        XCTAssertEqual(result.workouts.count, 1)
        XCTAssertEqual(result.workouts[0].sets.map(\.weight), [0])
        XCTAssertEqual(result.workouts[0].sets[0].reps, 10)
    }

    func testCSVConvertsPoundsToKilograms() throws {
        let result = try StrongImportParser.parse("Date,Exercise,Weight,Reps\n2025-01-01,Bench Press,10 lb,5")

        XCTAssertEqual(result.workouts[0].sets[0].weight, 4.5359237, accuracy: 0.000001)
    }

    func testCSVRejectsMalformedPartialRowsButKeepsValidRows() throws {
        let csv = "Date,Exercise,Weight,Reps\n2025-01-01,Squat,0,5\nnot-a-date,Deadlift,20 kg,3\n2025-01-01,Bench Press,-5 kg,5\n2025-01-01,Row,NaN kg,8\n2025-01-01,Pull Up,,8"

        let result = try StrongImportParser.parse(csv)

        XCTAssertEqual(result.workouts.count, 1)
        XCTAssertEqual(result.workouts[0].sets.count, 1)
        XCTAssertEqual(result.workouts[0].sets[0].weight, 0)
        XCTAssertEqual(result.failedRows, 4)
    }

    func testJSONCountsInvalidSetsAndSkipsEmptyWorkouts() throws {
        let json = #"{"workouts":[{"name":"Mixed","date":"2025-01-01","exercises":[{"name":"Bench Press","sets":[{"weight":20,"reps":5},{"weight":-1,"reps":5}]}]},{"name":"Empty","date":"2025-01-02","exercises":[]},{"name":"Bad date","date":"not-a-date","exercises":[]}]}"#

        let result = try StrongImportParser.parse(json)

        XCTAssertEqual(result.workouts.count, 1)
        XCTAssertEqual(result.workouts[0].sets.count, 1)
        XCTAssertEqual(result.skippedRows, 1)
        XCTAssertEqual(result.failedRows, 2)
    }

    func testSharedTextParsesPoundsAndCountsMalformedSetLines() throws {
        let text = "Push Day\nMonday, January 6, 2025 at 6:30 AM\nBench Press\nSet 1: 100 lb × 5\nSet 2: invalid"

        let result = try StrongImportParser.parse(text)

        XCTAssertEqual(result.workouts.count, 1)
        XCTAssertEqual(result.workouts[0].title, "Push Day")
        XCTAssertEqual(result.workouts[0].sets[0].weight, 45.359237, accuracy: 0.000001)
        XCTAssertEqual(result.workouts[0].sets[0].reps, 5)
        XCTAssertEqual(result.failedRows, 1)
    }

    func testCSVParsesDurationColumnFormattedAsHoursAndMinutes() throws {
        let result = try StrongImportParser.parse("Date,Exercise,Weight,Reps,Duration\n2025-01-01,Bench Press,20 kg,5,1h 5m")

        XCTAssertEqual(result.workouts.count, 1)
        XCTAssertEqual(result.workouts[0].durationMinutes, 65)
    }

    func testCSVParsesDurationColumnFormattedAsHoursOnly() throws {
        let result = try StrongImportParser.parse("Date,Exercise,Weight,Reps,Duration\n2025-01-01,Bench Press,20 kg,5,1h")

        XCTAssertEqual(result.workouts.count, 1)
        XCTAssertEqual(result.workouts[0].durationMinutes, 60)
    }

    func testCSVParsesLegacyWorkoutDurationColumnFormattedAsMinutes() throws {
        let result = try StrongImportParser.parse("Date,Exercise,Weight,Reps,Workout Duration\n2025-01-01,Bench Press,20 kg,5,45m")

        XCTAssertEqual(result.workouts.count, 1)
        XCTAssertEqual(result.workouts[0].durationMinutes, 45)
    }

    func testCSVParsesBareIntegerDurationAsMinutes() throws {
        let result = try StrongImportParser.parse("Date,Exercise,Weight,Reps,Duration\n2025-01-01,Bench Press,20 kg,5,75")

        XCTAssertEqual(result.workouts.count, 1)
        XCTAssertEqual(result.workouts[0].durationMinutes, 75)
    }

    func testCSVClampsNegativeAndOversizedDurationValues() throws {
        let negative = try StrongImportParser.parse("Date,Exercise,Weight,Reps,Duration\n2025-01-01,Bench Press,20 kg,5,-15")
        XCTAssertEqual(negative.workouts.count, 1)
        XCTAssertEqual(negative.workouts[0].durationMinutes, 0)

        let oversized = try StrongImportParser.parse("Date,Exercise,Weight,Reps,Duration\n2025-01-01,Bench Press,20 kg,5,99999")
        XCTAssertEqual(oversized.workouts.count, 1)
        XCTAssertEqual(oversized.workouts[0].durationMinutes, 240)
    }

    func testCSVMissingDurationValueDefaultsToZeroWithoutFailingRow() throws {
        let result = try StrongImportParser.parse("Date,Exercise,Weight,Reps,Duration\n2025-01-01,Bench Press,20 kg,5,")

        XCTAssertEqual(result.workouts.count, 1)
        XCTAssertEqual(result.workouts[0].durationMinutes, 0)
        XCTAssertEqual(result.workouts[0].sets.count, 1)
        XCTAssertEqual(result.workouts[0].sets[0].weight, 20)
        XCTAssertEqual(result.workouts[0].sets[0].reps, 5)
        XCTAssertEqual(result.failedRows, 0)
        XCTAssertEqual(result.skippedRows, 0)
    }

    func testCSVUnparseableDurationTextFallsBackToZeroWithoutFailingRow() throws {
        let result = try StrongImportParser.parse("Date,Exercise,Weight,Reps,Duration\n2025-01-01,Bench Press,20 kg,5,soon")

        XCTAssertEqual(result.workouts.count, 1)
        XCTAssertEqual(result.workouts[0].durationMinutes, 0)
        XCTAssertEqual(result.workouts[0].sets.count, 1)
        XCTAssertEqual(result.failedRows, 0)
        XCTAssertEqual(result.skippedRows, 0)
    }

    func testCSVGroupedWorkoutDurationIsNotSummedAcrossRepeatedRows() throws {
        let csv = "Date,Exercise,Weight,Reps,Duration\n2025-01-01,Bench Press,20 kg,5,30m\n2025-01-01,Squat,40 kg,5,30m\n2025-01-01,Row,10 kg,8,30m"

        let result = try StrongImportParser.parse(csv)

        XCTAssertEqual(result.workouts.count, 1)
        XCTAssertEqual(result.workouts[0].sets.count, 3)
        XCTAssertEqual(result.workouts[0].durationMinutes, 30)
    }

    func testCSVGroupedWorkoutDurationKeepsFirstRowValueWhenRowsDiffer() throws {
        let csv = "Date,Exercise,Weight,Reps,Duration\n2025-01-01,Bench Press,20 kg,5,30m\n2025-01-01,Squat,40 kg,5,45m\n2025-01-01,Row,10 kg,8,20m"

        let result = try StrongImportParser.parse(csv)

        XCTAssertEqual(result.workouts.count, 1)
        XCTAssertEqual(result.workouts[0].sets.count, 3)
        XCTAssertEqual(result.workouts[0].durationMinutes, 30)
    }

    func testJSONImportDefaultsDurationToZero() throws {
        let result = try StrongImportParser.parse(#"{"workouts":[{"name":"Bodyweight","date":"2025-01-01","exercises":[{"name":"Push Up","sets":[{"weight":0,"reps":10}]}]}]}"#)

        XCTAssertEqual(result.workouts.count, 1)
        XCTAssertEqual(result.workouts[0].durationMinutes, 0)
    }

    func testDuplicateWorkoutDetectionMatchesTitleDateAndSets() {
        let date = Date(timeIntervalSince1970: 1_735_689_600)
        let storedSet = ExerciseSet(exercise: "Bench Press", weight: 0, reps: 10, setNumber: 1, primaryMuscle: .chest)
        let stored = Workout(date: date, title: "Bodyweight", durationMinutes: 0, sets: [storedSet])
        let importedSet = ImportedSet(exercise: "bench press", weight: 0, reps: 10)
        let imported = ImportedWorkout(title: "bodyweight", date: date.addingTimeInterval(30), sets: [importedSet])

        XCTAssertTrue(StrongImportView.isDuplicate(stored, imported))
    }
}
