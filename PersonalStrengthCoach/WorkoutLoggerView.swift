import SwiftUI
import SwiftData
import OSLog

struct EditableSet: Identifiable, Hashable {
    let id = UUID()
    /// The persisted row this draft came from; nil means "added in this session".
    let existingModel: ExerciseSet?
    var weight: Double
    var reps: Int

    init(existingModel: ExerciseSet? = nil, weight: Double = 0, reps: Int = 8) {
        self.existingModel = existingModel
        self.weight = weight
        self.reps = reps
    }

    init(model: ExerciseSet) {
        self.init(existingModel: model, weight: model.weight, reps: model.reps)
    }

    // Identity is the draft's own UUID: SwiftUI diffs by `id`, and reaching into a
    // `PersistentModel`'s hash would be pointless work and a hazard once it's deleted.
    static func == (lhs: EditableSet, rhs: EditableSet) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct LoggedExercise: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let primaryMuscle: MuscleGroup
    var sets: [EditableSet] = [EditableSet(), EditableSet(), EditableSet()]
}

extension LoggedExercise {
    static func draftExercises(from routine: Routine) -> [LoggedExercise] {
        routine.exercises.sorted { $0.order < $1.order }.map { routineExercise in
            let setCount = max(1, routineExercise.targetSets)
            let sets = (0..<setCount).map { _ in
                EditableSet(weight: routineExercise.targetWeight ?? 0, reps: routineExercise.targetReps)
            }
            return LoggedExercise(name: routineExercise.exercise, primaryMuscle: routineExercise.primaryMuscle, sets: sets)
        }
    }

    static func draftExercises(from workout: Workout) -> [LoggedExercise] {
        WorkoutEditorLogic.editableExercises(from: workout.sets)
    }
}

/// Pure helpers for editing a logged workout, factored out of `WorkoutLoggerView`
/// so the set-diff and prefill logic can be unit-tested without a `ModelContext`.
enum WorkoutEditorLogic {
    static func removedSetIDs(original: Set<ObjectIdentifier>, remaining: Set<ObjectIdentifier>) -> Set<ObjectIdentifier> {
        original.subtracting(remaining)
    }

    /// Rebuilds editable exercise blocks from a workout's unordered `sets`
    /// relationship. Blocks are keyed on the raw `exercise` string (never
    /// `normalizedExercise`, which would rename the user's entry), ordered
    /// alphabetically to match `WorkoutDetailView`, and each block's sets are
    /// ordered by `setNumber` (tie-broken on weight/reps for determinism).
    ///
    /// Two same-name blocks in one workout merge into one: `ExerciseSet` stores no
    /// intra-workout ordering, so their original segmentation is unrecoverable. Every
    /// set, weight, and rep survives — only the split is lost, and no analytic reads
    /// `setNumber`.
    static func editableExercises(from sets: [ExerciseSet]) -> [LoggedExercise] {
        Dictionary(grouping: sets, by: \.exercise)
            .sorted { $0.key < $1.key }
            .map { name, group in
                let ordered = group.sorted { ($0.setNumber, $0.weight, $0.reps) < ($1.setNumber, $1.weight, $1.reps) }
                return LoggedExercise(
                    name: name,
                    primaryMuscle: ordered.first?.primaryMuscle ?? .core,
                    sets: ordered.map(EditableSet.init(model:))
                )
            }
    }
}

struct WorkoutLoggerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let workout: Workout?          // nil == log a new workout
    @State private var title = "Workout"
    @State private var date = Date.now
    @State private var sessionStart = Date.now
    @State private var durationMinutes = 0
    @State private var exercises: [LoggedExercise] = []
    @State private var hasLoadedDraft = false
    @State private var showingExercisePicker = false
    @State private var showingRoutinePicker = false
    @State private var routinePendingReplacement: Routine?
    @State private var showingRoutineReplacementConfirmation = false
    @State private var showingEmptyAlert = false
    @State private var saveError: String?
    private let logger = Logger(subsystem: "com.personalstrengthcoach.app", category: "Persistence")

    // Explicit init so `WorkoutLoggerView()` still resolves once `workout` is a
    // stored non-defaulted property: adding it removes the synthesized default init,
    // and the memberwise one is private (the `@State` are), so it can't be seen
    // from `RootView`.
    init(workout: Workout? = nil) {
        self.workout = workout
    }

    private var isEditing: Bool { workout != nil }

    var body: some View {
        NavigationStack {
            List {
                Section("Workout") {
                    TextField("Workout name", text: $title)
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    if isEditing {
                        Stepper("Duration: \(durationMinutes) min", value: $durationMinutes, in: 1...240)
                    } else {
                        Button { showingRoutinePicker = true } label: {
                            Label("Start from a routine", systemImage: "list.bullet.rectangle")
                        }
                    }
                }

                if exercises.isEmpty {
                    ContentUnavailableView("Add your first exercise", systemImage: "dumbbell.fill", description: Text("Choose from the exercise library or create your own."))
                        .listRowBackground(Color.clear)
                }

                ForEach($exercises) { $exercise in
                    ExerciseLoggerCard(exercise: $exercise) {
                        exercises.removeAll { $0.id == exercise.id }
                    }
                }

                Section {
                    Button { showingExercisePicker = true } label: {
                        Label("Add exercise", systemImage: "plus.circle.fill")
                            .fontWeight(.semibold)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Workout" : "Log Workout")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: loadDraftIfNeeded)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.semibold) }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePicker { exercise in
                    exercises.append(LoggedExercise(name: exercise.name, primaryMuscle: exercise.primaryMuscle))
                    showingExercisePicker = false
                }
            }
            .sheet(isPresented: $showingRoutinePicker) {
                RoutineStartPicker { routine in
                    if exercises.isEmpty {
                        applyRoutine(routine)
                    } else {
                        routinePendingReplacement = routine
                        showingRoutineReplacementConfirmation = true
                    }
                    showingRoutinePicker = false
                }
            }
            .confirmationDialog("Replace current workout?", isPresented: $showingRoutineReplacementConfirmation, titleVisibility: .visible) {
                Button("Replace", role: .destructive) {
                    if let routine = routinePendingReplacement { applyRoutine(routine) }
                    routinePendingReplacement = nil
                }
                Button("Keep Editing", role: .cancel) { routinePendingReplacement = nil }
            } message: { Text("Starting from this routine will replace the exercises you've already added.") }
            .alert("Add an exercise first", isPresented: $showingEmptyAlert) {
                Button("OK", role: .cancel) { }
            } message: { Text("A workout needs at least one exercise and one working set.") }
            .alert("Couldn’t save workout", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) { }
            } message: { Text(saveError ?? "Your workout was not saved. Try again.") }
        }
    }

    private func applyRoutine(_ routine: Routine) {
        title = routine.name
        exercises = LoggedExercise.draftExercises(from: routine)
    }

    private func loadDraftIfNeeded() {
        guard !hasLoadedDraft else { return }
        hasLoadedDraft = true
        guard let workout else { return }
        title = workout.title
        date = workout.date
        durationMinutes = workout.durationMinutes
        exercises = LoggedExercise.draftExercises(from: workout)
    }

    private func save() {
        let completedExercises = exercises.filter { !$0.sets.isEmpty }
        // Both modes: an empty workout is an error, never an implicit delete —
        // deletion has to be explicit and confirmed.
        guard !completedExercises.isEmpty else { showingEmptyAlert = true; return }
        let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Workout" : title

        // Reuse the existing workout when editing. `calories` and `notes` are never
        // assigned here, so they're preserved structurally — do NOT "rebuild the
        // Workout", which would zero them on seeded/imported sessions.
        let targetWorkout = workout ?? Workout(date: date, title: resolvedTitle, durationMinutes: WorkoutTimerEngine.elapsedMinutes(start: sessionStart, end: .now))
        if workout == nil { context.insert(targetWorkout) }
        targetWorkout.date = date
        targetWorkout.title = resolvedTitle
        if isEditing { targetWorkout.durationMinutes = WorkoutTimerEngine.clampedMinutes(durationMinutes) }

        // Delete the persisted sets the user dropped from the draft.
        let originalSets = workout?.sets ?? []
        let originalByID = Dictionary(uniqueKeysWithValues: originalSets.map { (ObjectIdentifier($0), $0) })
        let remainingIDs = Set(completedExercises.flatMap(\.sets).compactMap { $0.existingModel.map(ObjectIdentifier.init) })
        for removedID in WorkoutEditorLogic.removedSetIDs(original: Set(originalByID.keys), remaining: remainingIDs) {
            if let removedSet = originalByID[removedID] { context.delete(removedSet) }
        }

        // Update kept sets in place, insert new ones, renumber per exercise block.
        // `exercise`/`normalizedExercise` are deliberately not reassigned on kept
        // rows — editing exercise identity is a non-goal and the UI has no name field.
        var finalSets: [ExerciseSet] = []
        for exercise in completedExercises {
            for (index, loggedSet) in exercise.sets.enumerated() {
                let set = loggedSet.existingModel ?? ExerciseSet(exercise: exercise.name, weight: loggedSet.weight, reps: loggedSet.reps, setNumber: index + 1, primaryMuscle: exercise.primaryMuscle)
                set.weight = loggedSet.weight
                set.reps = loggedSet.reps
                set.setNumber = index + 1
                set.workout = targetWorkout
                if loggedSet.existingModel == nil { context.insert(set) }
                finalSets.append(set)
            }
        }
        targetWorkout.sets = finalSets

        do {
            try context.save()
            dismiss()
        } catch {
            logger.error("Workout save failed")
            context.rollback()
            saveError = "Your workout was not saved. Try again."
        }
    }
}

private struct ExerciseLoggerCard: View {
    @Binding var exercise: LoggedExercise
    let remove: () -> Void

    var body: some View {
        Section {
            ForEach($exercise.sets) { $set in
                HStack {
                    Text("\(exercise.sets.firstIndex(where: { $0.id == set.id }).map { $0 + 1 } ?? 0)")
                        .font(.caption.weight(.bold)).foregroundStyle(.secondary).frame(width: 18)
                    NumericFieldDouble(value: $set.weight, title: "kg")
                    NumericFieldInt(value: $set.reps, title: "reps")
                    Button(role: .destructive) { exercise.sets.removeAll { $0.id == set.id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            Button { exercise.sets.append(EditableSet()) } label: { Label("Add set", systemImage: "plus") }
        } header: {
            HStack { VStack(alignment: .leading) { Text(exercise.name).font(.headline); Text(exercise.primaryMuscle.rawValue).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button(role: .destructive, action: remove) { Image(systemName: "trash") }.buttonStyle(.borderless) }
        }
    }
}

private struct NumericFieldInt: View {
    @Binding var value: Int
    let title: String
    var body: some View { TextField(title, value: $value, format: .number).keyboardType(.numberPad).multilineTextAlignment(.center).textFieldStyle(.roundedBorder).frame(maxWidth: 90) }
}

private struct NumericFieldDouble: View {
    @Binding var value: Double
    let title: String
    var body: some View { TextField(title, value: $value, format: .number.precision(.fractionLength(1))).keyboardType(.decimalPad).multilineTextAlignment(.center).textFieldStyle(.roundedBorder).frame(maxWidth: 90) }
}

struct RoutineStartPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Routine.name) private var routines: [Routine]
    let select: (Routine) -> Void

    var body: some View {
        NavigationStack {
            List {
                if routines.isEmpty {
                    ContentUnavailableView("No saved routines", systemImage: "list.bullet.rectangle", description: Text("Create a routine from Workout History to start sessions faster."))
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(routines) { routine in
                        Button { select(routine) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(routine.name).font(.headline)
                                Text("\(routine.exercises.count) exercise\(routine.exercises.count == 1 ? "" : "s")")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Start Routine")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct ExercisePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CustomExercise.name) private var customExercises: [CustomExercise]
    @State private var search = ""
    @State private var showingCreator = false
    let select: (LibraryExercise) -> Void

    private var exercises: [LibraryExercise] {
        let custom = customExercises.map { LibraryExercise(name: $0.name, primaryMuscle: $0.primaryMuscle) }
        let all = ExerciseLibrary.seeded + custom
        guard !search.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.primaryMuscle.rawValue.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(MuscleGroup.allCases) { muscle in
                    let choices = exercises.filter { $0.primaryMuscle == muscle }
                    if !choices.isEmpty { Section(muscle.rawValue) { ForEach(choices) { exercise in Button(exercise.name) { select(exercise) }.foregroundStyle(.primary) } } }
                }
            }
            .searchable(text: $search, prompt: "Search exercises")
            .navigationTitle("Add Exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button { showingCreator = true } label: { Label("New Exercise", systemImage: "plus") } }
            }
            .sheet(isPresented: $showingCreator) { NewExerciseView { exercise in select(exercise); showingCreator = false } }
        }
    }
}

struct NewExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var muscle: MuscleGroup = .chest
    @State private var saveError: String?
    private let logger = Logger(subsystem: "com.personalstrengthcoach.app", category: "Persistence")
    let created: (LibraryExercise) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Exercise name", text: $name)
                Picker("Primary muscle", selection: $muscle) { ForEach(MuscleGroup.allCases) { Text($0.rawValue).tag($0) } }
            }
            .navigationTitle("New Exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add") { add() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .alert("Couldn’t save exercise", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) { }
            } message: { Text(saveError ?? "Your exercise was not saved. Try again.") }
        }
    }

    private func add() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        context.insert(CustomExercise(name: cleanName, primaryMuscle: muscle))
        do {
            try context.save()
            created(LibraryExercise(name: cleanName, primaryMuscle: muscle))
            dismiss()
        } catch {
            logger.error("Custom exercise save failed")
            context.rollback()
            saveError = "Your exercise was not saved. Try again."
        }
    }
}
