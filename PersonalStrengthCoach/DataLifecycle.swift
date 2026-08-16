import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct WorkoutExport: Codable {
    let date: Date
    let title: String
    let durationMinutes: Int
    let calories: Int
    let notes: String
    let sets: [SetExport]
}

struct SetExport: Codable {
    let exercise: String
    let normalizedExercise: String
    let weight: Double
    let reps: Int
    let setNumber: Int
    let primaryMuscle: String
}

struct RecoveryExport: Codable {
    let date: Date
    let sleepHours: Double
    let hrv: Double
    let restingHeartRate: Double
    let weightKg: Double
    let sleepSampleCount: Int
    let hrvSampleCount: Int
    let restingHeartRateSampleCount: Int
    let bodyMassSampleCount: Int
}

struct CustomExerciseExport: Codable {
    let name: String
    let primaryMuscle: String
    let createdAt: Date
}

struct RoutineExerciseExport: Codable {
    let exercise: String
    let normalizedExercise: String
    let primaryMuscle: String
    let order: Int
    let targetSets: Int
    let targetReps: Int
    let targetWeight: Double?
}

struct RoutineExport: Codable {
    let name: String
    let createdAt: Date
    let exercises: [RoutineExerciseExport]
}

struct PersonalStrengthExport: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let workouts: [WorkoutExport]
    let recovery: [RecoveryExport]
    let customExercises: [CustomExerciseExport]
    let routines: [RoutineExport]
}

struct DataExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { .init(regularFileWithContents: data) }
}

enum AppSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Workout.self, ExerciseSet.self, DailyRecovery.self, CustomExercise.self] }

    @Model
    final class Workout {
        var date: Date
        var title: String
        var durationMinutes: Int
        var calories: Int
        var notes: String
        @Relationship(deleteRule: .cascade, inverse: \ExerciseSet.workout) var sets: [ExerciseSet]

        init(date: Date = .now, title: String, durationMinutes: Int, calories: Int = 0, notes: String = "", sets: [ExerciseSet] = []) {
            self.date = date; self.title = title; self.durationMinutes = durationMinutes
            self.calories = calories; self.notes = notes; self.sets = sets
        }
    }

    @Model
    final class ExerciseSet {
        var exercise: String
        var normalizedExercise: String
        var weight: Double
        var reps: Int
        var setNumber: Int
        var primaryMuscleRaw: String
        var workout: Workout?

        init(exercise: String, normalizedExercise: String, weight: Double, reps: Int, setNumber: Int, primaryMuscleRaw: String) {
            self.exercise = exercise; self.normalizedExercise = normalizedExercise
            self.weight = weight; self.reps = reps; self.setNumber = setNumber
            self.primaryMuscleRaw = primaryMuscleRaw
        }
    }

    @Model
    final class DailyRecovery {
        var date: Date
        var sleepHours: Double
        var hrv: Double
        var restingHeartRate: Double
        var weightKg: Double

        init(date: Date, sleepHours: Double, hrv: Double, restingHeartRate: Double, weightKg: Double) {
            self.date = date
            self.sleepHours = sleepHours
            self.hrv = hrv
            self.restingHeartRate = restingHeartRate
            self.weightKg = weightKg
        }
    }

    @Model
    final class CustomExercise {
        var name: String
        var primaryMuscleRaw: String
        var createdAt: Date

        init(name: String, primaryMuscleRaw: String, createdAt: Date = .now) {
            self.name = name
            self.primaryMuscleRaw = primaryMuscleRaw
            self.createdAt = createdAt
        }
    }
}

enum AppSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [Workout.self, ExerciseSet.self, DailyRecovery.self, CustomExercise.self, Routine.self, RoutineExercise.self] }

    @Model
    final class Workout {
        var date: Date
        var title: String
        var durationMinutes: Int
        var calories: Int
        var notes: String
        @Relationship(deleteRule: .cascade, inverse: \ExerciseSet.workout) var sets: [ExerciseSet]

        init(date: Date = .now, title: String, durationMinutes: Int, calories: Int = 0, notes: String = "", sets: [ExerciseSet] = []) {
            self.date = date; self.title = title; self.durationMinutes = durationMinutes
            self.calories = calories; self.notes = notes; self.sets = sets
        }
    }

    @Model
    final class ExerciseSet {
        var exercise: String
        var normalizedExercise: String
        var weight: Double
        var reps: Int
        var setNumber: Int
        var primaryMuscleRaw: String
        var workout: Workout?

        init(exercise: String, normalizedExercise: String, weight: Double, reps: Int, setNumber: Int, primaryMuscleRaw: String) {
            self.exercise = exercise; self.normalizedExercise = normalizedExercise
            self.weight = weight; self.reps = reps; self.setNumber = setNumber
            self.primaryMuscleRaw = primaryMuscleRaw
        }
    }

    @Model
    final class DailyRecovery {
        var date: Date
        var sleepHours: Double
        var hrv: Double
        var restingHeartRate: Double
        var weightKg: Double

        init(date: Date, sleepHours: Double, hrv: Double, restingHeartRate: Double, weightKg: Double) {
            self.date = date
            self.sleepHours = sleepHours
            self.hrv = hrv
            self.restingHeartRate = restingHeartRate
            self.weightKg = weightKg
        }
    }

    @Model
    final class CustomExercise {
        var name: String
        var primaryMuscleRaw: String
        var createdAt: Date

        init(name: String, primaryMuscleRaw: String, createdAt: Date = .now) {
            self.name = name
            self.primaryMuscleRaw = primaryMuscleRaw
            self.createdAt = createdAt
        }
    }

    @Model
    final class Routine {
        var name: String
        var createdAt: Date
        @Relationship(deleteRule: .cascade, inverse: \RoutineExercise.routine) var exercises: [RoutineExercise]

        init(name: String, createdAt: Date = .now, exercises: [RoutineExercise] = []) {
            self.name = name; self.createdAt = createdAt; self.exercises = exercises
        }
    }

    @Model
    final class RoutineExercise {
        var exercise: String
        var normalizedExercise: String
        var primaryMuscleRaw: String
        var order: Int
        var targetSets: Int
        var targetReps: Int
        var targetWeight: Double?
        var routine: Routine?

        init(exercise: String, normalizedExercise: String, primaryMuscleRaw: String, order: Int, targetSets: Int, targetReps: Int, targetWeight: Double? = nil) {
            self.exercise = exercise; self.normalizedExercise = normalizedExercise
            self.primaryMuscleRaw = primaryMuscleRaw; self.order = order
            self.targetSets = targetSets; self.targetReps = targetReps; self.targetWeight = targetWeight
        }
    }
}

enum AppSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] { [Workout.self, ExerciseSet.self, DailyRecovery.self, CustomExercise.self, Routine.self, RoutineExercise.self] }
}

enum AppSchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Workout.self, ExerciseSet.self, DailyRecovery.self, CustomExercise.self, Routine.self, RoutineExercise.self, WorkoutInProgress.self, WorkoutInProgressSet.self]
    }
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [AppSchemaV1.self, AppSchemaV2.self, AppSchemaV3.self, AppSchemaV4.self] }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: AppSchemaV1.self, toVersion: AppSchemaV2.self),
            .lightweight(fromVersion: AppSchemaV2.self, toVersion: AppSchemaV3.self),
            .lightweight(fromVersion: AppSchemaV3.self, toVersion: AppSchemaV4.self),
        ]
    }
}

struct DataManagementView: View {
    @Environment(\.modelContext) private var context
    @Query private var workouts: [Workout]
    @Query private var recovery: [DailyRecovery]
    @Query private var customExercises: [CustomExercise]
    @Query private var routines: [Routine]
    @State private var exportDocument: DataExportDocument?
    @State private var showingExporter = false
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Your data") {
                    Button { prepareExport() } label: { Label("Export my data", systemImage: "square.and.arrow.up") }
                    Text("Exports workouts, recovery records, custom exercises, and routines as JSON. HealthKit history itself is not changed.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Danger zone") {
                    Button("Delete all local data", role: .destructive) { showingDeleteConfirmation = true }
                    Text("This removes data stored by Personal Strength Coach. It does not delete records from Apple Health.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete all local data?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { deleteAllData() }
                Button("Cancel", role: .cancel) { }
            } message: { Text("This action cannot be undone unless you have an export.") }
            .alert("Data operation failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { }
            } message: { Text(errorMessage ?? "Please try again.") }
            .fileExporter(isPresented: $showingExporter, document: exportDocument, contentType: .json, defaultFilename: "PersonalStrengthCoach-Export") { result in
                if case .failure = result { errorMessage = "The export could not be written." }
            }
        }
    }

    private func prepareExport() {
        let payload = PersonalStrengthExport(
            schemaVersion: 4,
            exportedAt: .now,
            workouts: workouts.map { workout in
                WorkoutExport(date: workout.date, title: workout.title, durationMinutes: workout.durationMinutes, calories: workout.calories, notes: workout.notes, sets: workout.sets.map { set in
                    SetExport(exercise: set.exercise, normalizedExercise: set.normalizedExercise, weight: set.weight, reps: set.reps, setNumber: set.setNumber, primaryMuscle: set.primaryMuscleRaw)
                })
            },
            recovery: recovery.map { RecoveryExport(date: $0.date, sleepHours: $0.sleepHours, hrv: $0.hrv, restingHeartRate: $0.restingHeartRate, weightKg: $0.weightKg, sleepSampleCount: $0.sleepSampleCount, hrvSampleCount: $0.hrvSampleCount, restingHeartRateSampleCount: $0.restingHeartRateSampleCount, bodyMassSampleCount: $0.bodyMassSampleCount) },
            customExercises: customExercises.map { CustomExerciseExport(name: $0.name, primaryMuscle: $0.primaryMuscleRaw, createdAt: $0.createdAt) },
            routines: routines.map { routine in
                // SwiftData to-many relationship array order is not guaranteed stable, so
                // exercises must be sorted by `order` explicitly (mirrors RoutineEngine.buildWorkout).
                let orderedExercises = routine.exercises.sorted { $0.order < $1.order }
                return RoutineExport(name: routine.name, createdAt: routine.createdAt, exercises: orderedExercises.map { exercise in
                    RoutineExerciseExport(exercise: exercise.exercise, normalizedExercise: exercise.normalizedExercise, primaryMuscle: exercise.primaryMuscleRaw, order: exercise.order, targetSets: exercise.targetSets, targetReps: exercise.targetReps, targetWeight: exercise.targetWeight)
                })
            }
        )
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            exportDocument = DataExportDocument(data: try encoder.encode(payload))
            showingExporter = true
        } catch {
            errorMessage = "The export could not be prepared."
        }
    }

    private func deleteAllData() {
        do {
            try context.delete(model: Workout.self)
            try context.delete(model: ExerciseSet.self)
            try context.delete(model: DailyRecovery.self)
            try context.delete(model: CustomExercise.self)
            try context.delete(model: Routine.self)
            try context.delete(model: RoutineExercise.self)
            try context.delete(model: WorkoutInProgress.self)
            try context.delete(model: WorkoutInProgressSet.self)
            try context.save()
        } catch {
            context.rollback()
            errorMessage = "Your local data could not be deleted."
        }
    }
}
