import SwiftUI
import SwiftData
import OSLog

struct DraftRoutineExercise: Identifiable {
    let id = UUID()
    let existingModel: RoutineExercise?
    var exercise: String
    var normalizedExercise: String
    var primaryMuscle: MuscleGroup
    var targetSets: Int
    var targetReps: Int
    var targetWeight: Double?

    init(existingModel: RoutineExercise? = nil, exercise: String, normalizedExercise: String? = nil, primaryMuscle: MuscleGroup, targetSets: Int = 3, targetReps: Int = 8, targetWeight: Double? = nil) {
        self.existingModel = existingModel
        self.exercise = exercise
        self.normalizedExercise = normalizedExercise ?? ExerciseCatalog.normalize(exercise)
        self.primaryMuscle = primaryMuscle
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetWeight = targetWeight
    }

    init(model: RoutineExercise) {
        self.init(
            existingModel: model,
            exercise: model.exercise,
            normalizedExercise: model.normalizedExercise,
            primaryMuscle: model.primaryMuscle,
            targetSets: model.targetSets,
            targetReps: model.targetReps,
            targetWeight: model.targetWeight
        )
    }

    init(libraryExercise: LibraryExercise) {
        self.init(exercise: libraryExercise.name, primaryMuscle: libraryExercise.primaryMuscle)
    }
}

enum RoutineEditorLogic {
    static func removedExerciseIDs(original: Set<ObjectIdentifier>, remaining: Set<ObjectIdentifier>) -> Set<ObjectIdentifier> {
        original.subtracting(remaining)
    }

    static func finalOrderValues(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        return Array(0..<count)
    }
}

struct RoutinesListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Routine.createdAt, order: .reverse) private var routines: [Routine]
    @State private var showingCreator = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if routines.isEmpty {
                ContentUnavailableView("No saved routines", systemImage: "list.bullet.rectangle", description: Text("Create a template for sessions you repeat often."))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(routines) { routine in
                    NavigationLink { RoutineEditorView(routine: routine) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(routine.name).font(.headline)
                            Text("\(routine.exercises.count) exercise\(routine.exercises.count == 1 ? "" : "s")")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteRoutines)
            }
        }
        .navigationTitle("Routines")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingCreator = true } label: { Label("New Routine", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showingCreator) {
            NavigationStack { RoutineEditorView(routine: nil) }
        }
        .alert("Couldn’t update routines", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { }
        } message: { Text(errorMessage ?? "Please try again.") }
    }

    private func deleteRoutines(at offsets: IndexSet) {
        for index in offsets {
            context.delete(routines[index])
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            errorMessage = "The routine could not be deleted."
        }
    }
}

struct RoutineEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("weightUnit") private var weightUnitRawValue = WeightUnit.defaultUnit.rawValue

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRawValue) ?? .defaultUnit }
    let routine: Routine?

    @State private var name = ""
    @State private var exercises: [DraftRoutineExercise] = []
    @State private var hasLoadedDraft = false
    @State private var showingExercisePicker = false
    @State private var showingDeleteConfirmation = false
    @State private var saveError: String?
    private let logger = Logger(subsystem: "com.personalstrengthcoach.app", category: "Persistence")

    private var isEditing: Bool { routine != nil }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section("Routine") {
                TextField("Routine name", text: $name)
            }

            Section("Exercises") {
                if exercises.isEmpty {
                    ContentUnavailableView("No exercises", systemImage: "dumbbell.fill", description: Text("Add exercises now, or save an empty routine for rest days."))
                        .listRowBackground(Color.clear)
                }
                ForEach($exercises) { $exercise in
                    RoutineExerciseEditorRow(exercise: $exercise, weightUnit: weightUnit)
                }
                .onMove(perform: moveExercises)
                .onDelete(perform: deleteExercises)

                Button { showingExercisePicker = true } label: {
                    Label("Add exercise", systemImage: "plus.circle.fill")
                        .fontWeight(.semibold)
                }
            }

            if isEditing {
                Section {
                    Button("Delete Routine", role: .destructive) { showingDeleteConfirmation = true }
                }
            }
        }
        .navigationTitle(isEditing ? "Edit Routine" : "New Routine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.semibold).disabled(trimmedName.isEmpty) }
            ToolbarItem(placement: .topBarTrailing) { EditButton().disabled(exercises.count < 2) }
        }
        .onAppear(perform: loadDraftIfNeeded)
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePicker { exercise in
                exercises.append(DraftRoutineExercise(libraryExercise: exercise))
                showingExercisePicker = false
            }
        }
        .confirmationDialog("Delete routine?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Routine", role: .destructive) { deleteRoutine() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("This removes the template, but logged workouts stay in your history.") }
        .alert("Couldn’t save routine", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: { Text(saveError ?? "Your routine was not saved. Try again.") }
    }

    private func loadDraftIfNeeded() {
        guard !hasLoadedDraft else { return }
        hasLoadedDraft = true
        guard let routine else { return }
        name = routine.name
        exercises = routine.exercises
            .sorted { $0.order < $1.order }
            .map(DraftRoutineExercise.init(model:))
    }

    private func moveExercises(from source: IndexSet, to destination: Int) {
        exercises.move(fromOffsets: source, toOffset: destination)
    }

    private func deleteExercises(at offsets: IndexSet) {
        exercises.remove(atOffsets: offsets)
    }

    private func save() {
        let cleanName = trimmedName
        guard !cleanName.isEmpty else { return }

        let targetRoutine = routine ?? Routine(name: cleanName)
        if routine == nil { context.insert(targetRoutine) }
        targetRoutine.name = cleanName

        let originalExercises = routine?.exercises ?? []
        let originalByID = Dictionary(uniqueKeysWithValues: originalExercises.map { (ObjectIdentifier($0), $0) })
        let originalIDs = Set(originalByID.keys)
        let remainingIDs = Set(exercises.compactMap { $0.existingModel.map(ObjectIdentifier.init) })
        let removedIDs = RoutineEditorLogic.removedExerciseIDs(original: originalIDs, remaining: remainingIDs)
        for removedID in removedIDs {
            if let removedExercise = originalByID[removedID] {
                context.delete(removedExercise)
            }
        }

        var finalExercises: [RoutineExercise] = []
        for (index, draft) in exercises.enumerated() {
            let model = draft.existingModel ?? RoutineExercise(
                exercise: draft.exercise,
                normalizedExercise: draft.normalizedExercise,
                primaryMuscle: draft.primaryMuscle,
                order: index,
                targetSets: max(1, draft.targetSets),
                targetReps: max(1, draft.targetReps),
                targetWeight: draft.targetWeight
            )
            model.exercise = draft.exercise
            model.normalizedExercise = draft.normalizedExercise
            model.primaryMuscleRaw = draft.primaryMuscle.rawValue
            model.order = index
            model.targetSets = max(1, draft.targetSets)
            model.targetReps = max(1, draft.targetReps)
            model.targetWeight = draft.targetWeight
            model.routine = targetRoutine
            if draft.existingModel == nil { context.insert(model) }
            finalExercises.append(model)
        }
        targetRoutine.exercises = finalExercises

        do {
            try context.save()
            dismiss()
        } catch {
            logger.error("Routine save failed")
            context.rollback()
            saveError = "Your routine was not saved. Try again."
        }
    }

    private func deleteRoutine() {
        guard let routine else { return }
        context.delete(routine)
        do {
            try context.save()
            dismiss()
        } catch {
            logger.error("Routine delete failed")
            context.rollback()
            saveError = "Your routine was not deleted. Try again."
        }
    }
}

private struct RoutineExerciseEditorRow: View {
    @Binding var exercise: DraftRoutineExercise
    let weightUnit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.exercise).font(.headline)
                Text(exercise.primaryMuscle.rawValue).font(.caption).foregroundStyle(.secondary)
            }
            Stepper("Target sets: \(exercise.targetSets)", value: $exercise.targetSets, in: 1...20)
            Stepper("Target reps: \(exercise.targetReps)", value: $exercise.targetReps, in: 1...50)
            Toggle("Target weight", isOn: Binding(
                get: { exercise.targetWeight != nil },
                set: { exercise.targetWeight = $0 ? (exercise.targetWeight ?? 0) : nil }
            ))
            if exercise.targetWeight != nil {
                HStack {
                    Text("Weight")
                    Spacer()
                    TextField(weightUnit.symbol, value: Binding(
                        get: { weightUnit.fromKilograms(exercise.targetWeight ?? 0) },
                        set: { exercise.targetWeight = max(0, weightUnit.toKilograms($0)) }
                    ), format: .number.precision(.fractionLength(1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
                    Text(weightUnit.symbol).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
