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
}

struct CustomExerciseExport: Codable {
    let name: String
    let primaryMuscle: String
    let createdAt: Date
}

struct PersonalStrengthExport: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let workouts: [WorkoutExport]
    let recovery: [RecoveryExport]
    let customExercises: [CustomExerciseExport]
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
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [AppSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

struct DataManagementView: View {
    @Environment(\.modelContext) private var context
    @Query private var workouts: [Workout]
    @Query private var recovery: [DailyRecovery]
    @Query private var customExercises: [CustomExercise]
    @State private var exportDocument: DataExportDocument?
    @State private var showingExporter = false
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Your data") {
                    Button { prepareExport() } label: { Label("Export my data", systemImage: "square.and.arrow.up") }
                    Text("Exports workouts, recovery records, and custom exercises as JSON. HealthKit history itself is not changed.")
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
            schemaVersion: 1,
            exportedAt: .now,
            workouts: workouts.map { workout in
                WorkoutExport(date: workout.date, title: workout.title, durationMinutes: workout.durationMinutes, calories: workout.calories, notes: workout.notes, sets: workout.sets.map { set in
                    SetExport(exercise: set.exercise, normalizedExercise: set.normalizedExercise, weight: set.weight, reps: set.reps, setNumber: set.setNumber, primaryMuscle: set.primaryMuscleRaw)
                })
            },
            recovery: recovery.map { RecoveryExport(date: $0.date, sleepHours: $0.sleepHours, hrv: $0.hrv, restingHeartRate: $0.restingHeartRate, weightKg: $0.weightKg) },
            customExercises: customExercises.map { CustomExerciseExport(name: $0.name, primaryMuscle: $0.primaryMuscleRaw, createdAt: $0.createdAt) }
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
            try context.save()
        } catch {
            context.rollback()
            errorMessage = "Your local data could not be deleted."
        }
    }
}
