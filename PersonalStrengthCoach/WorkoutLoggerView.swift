import SwiftUI
import SwiftData
import OSLog

struct EditableSet: Identifiable, Hashable {
    let id = UUID()
    /// The persisted row this draft came from; nil means "added in this session".
    let existingModel: ExerciseSet?
    var weight: Double
    var reps: Int
    var isCompleted: Bool
    var setType: SetType
    var rpe: Double?

    init(existingModel: ExerciseSet? = nil, weight: Double = 0, reps: Int = 8, isCompleted: Bool = false, setType: SetType = .working, rpe: Double? = nil) {
        self.existingModel = existingModel
        self.weight = weight
        self.reps = reps
        self.isCompleted = isCompleted
        self.setType = setType
        self.rpe = RPEEngine.validated(rpe)
    }

    init(model: ExerciseSet) {
        self.init(existingModel: model, weight: model.weight, reps: model.reps, isCompleted: true, setType: model.setType, rpe: model.rpe)
    }

    // Identity is the draft's own UUID: SwiftUI diffs by `id`, and reaching into a
    // `PersistentModel`'s hash would be pointless work and a hazard once it's deleted.
    static func == (lhs: EditableSet, rhs: EditableSet) -> Bool {
        lhs.id == rhs.id && lhs.weight == rhs.weight && lhs.reps == rhs.reps && lhs.isCompleted == rhs.isCompleted && lhs.setType == rhs.setType && lhs.rpe == rhs.rpe
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(weight)
        hasher.combine(reps)
        hasher.combine(isCompleted)
        hasher.combine(setType)
        hasher.combine(rpe)
    }
}

struct LoggedExercise: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let primaryMuscle: MuscleGroup
    var sets: [EditableSet] = [EditableSet(), EditableSet(), EditableSet()]
}

extension LoggedExercise {
    static func draftExercise(
        from exercise: LibraryExercise,
        previous: PreviousSetPerformance? = nil
    ) -> LoggedExercise {
        let sets = previous?.sets.map { EditableSet(weight: $0.weight, reps: $0.reps, setType: $0.setType) }
            ?? [EditableSet(), EditableSet(), EditableSet()]
        return LoggedExercise(name: exercise.name, primaryMuscle: exercise.primaryMuscle, sets: sets)
    }

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

    /// Selects safe defaults for the next draft row without carrying completion
    /// state or subjective effort from a previous set.
    static func nextSetDefaults(current: [EditableSet], previous: PreviousSetPerformance?) -> EditableSet {
        if let historical = previous?.sets[safe: current.count] {
            return EditableSet(weight: historical.weight, reps: historical.reps, setType: historical.setType)
        }
        if let last = current.last {
            return EditableSet(weight: last.weight, reps: last.reps, setType: last.setType)
        }
        return EditableSet()
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
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Workout.date, order: .reverse) private var allWorkouts: [Workout]
    @Query(sort: \WorkoutInProgress.lastUpdated, order: .reverse) private var inProgressSessions: [WorkoutInProgress]
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
    @State private var restEndsAt: Date?
    @State private var now = Date.now
    @State private var showingDiscardConfirmation = false
    @AppStorage("weightUnit") private var weightUnitRawValue = WeightUnit.defaultUnit.rawValue
    private let logger = Logger(subsystem: "com.personalstrengthcoach.app", category: "Persistence")

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRawValue) ?? .defaultUnit }

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
                    ExerciseLoggerCard(
                        exercise: $exercise,
                        previous: PreviousSetEngine.mostRecentPerformance(
                            for: exercise.name,
                            in: allWorkouts,
                            excluding: workout
                        ),
                        weightUnit: weightUnit
                    ) {
                        exercises.removeAll { $0.id == exercise.id }
                    } startRest: {
                        startRestTimer()
                    }
                }

                Section {
                    Button { showingExercisePicker = true } label: {
                        Label("Add exercise", systemImage: "plus.circle.fill")
                            .fontWeight(.semibold)
                    }
                }

                if !isEditing {
                    Section("Session") {
                        LabeledContent("Volume so far", value: weightUnit.formattedWithUnit(WorkoutInProgressEngine.volume(of: exercises), fractionDigits: 0))
                        LabeledContent("Elapsed", value: "\(WorkoutInProgressEngine.elapsedSeconds(start: sessionStart, now: now) / 60) min")
                        if let remaining = WorkoutInProgressEngine.remainingRestSeconds(endsAt: restEndsAt, now: now), remaining > 0 {
                            LabeledContent("Rest timer", value: "\(remaining / 60):\(String(format: "%02d", remaining % 60))")
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Workout" : "Log Workout")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: loadDraftIfNeeded)
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { persistDraft() }
            }
            .onChange(of: title) { _, _ in persistDraft() }
            .onChange(of: date) { _, _ in persistDraft() }
            .onChange(of: exercises) { _, _ in persistDraft() }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    now = .now
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEditing ? "Cancel" : "Discard") {
                        if isEditing { dismiss() } else { showingDiscardConfirmation = true }
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.semibold) }
            }
            .confirmationDialog("Discard workout draft?", isPresented: $showingDiscardConfirmation, titleVisibility: .visible) {
                Button("Discard Draft", role: .destructive) { discardDraft() }
                Button("Keep Editing", role: .cancel) { }
            } message: { Text("This removes the unfinished workout and all of its saved sets.") }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePicker { exercise in
                    let previous = PreviousSetEngine.mostRecentPerformance(
                        for: exercise.name,
                        in: allWorkouts,
                        excluding: workout
                    )
                    exercises.append(LoggedExercise.draftExercise(from: exercise, previous: previous))
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
        if let workout {
            title = workout.title
            date = workout.date
            durationMinutes = workout.durationMinutes
            exercises = LoggedExercise.draftExercises(from: workout)
            return
        }

        let resolved = WorkoutInProgressEngine.resolveActiveSession(among: inProgressSessions)
        for stray in resolved.strays {
            context.delete(stray)
        }
        if !resolved.strays.isEmpty {
            do {
                try context.save()
            } catch {
                logger.error("Duplicate workout draft cleanup failed")
                context.rollback()
                saveError = "Your unfinished workout could not be restored safely."
            }
        }

        guard let session = resolved.current else {
            persistDraft()
            return
        }
        title = session.title
        date = session.date
        sessionStart = session.sessionStart
        restEndsAt = session.restEndsAt
        let persistedSets = session.sets.map {
            PersistedDraftSet(
                exercise: $0.exercise,
                primaryMuscle: $0.primaryMuscle,
                exerciseOrder: $0.exerciseOrder,
                weight: $0.weight,
                reps: $0.reps,
                setNumber: $0.setNumber,
                isCompleted: $0.isCompleted,
                setType: $0.setType,
                rpe: $0.rpe
            )
        }
        exercises = WorkoutInProgressEngine.draftExercises(from: persistedSets)
    }

    private func persistDraft() {
        guard hasLoadedDraft, !isEditing else { return }
        let now = Date.now
        let session: WorkoutInProgress
        if let existing = inProgressSessions.first {
            session = existing
        } else {
            session = WorkoutInProgress(title: title, date: date, sessionStart: sessionStart, lastUpdated: now)
            context.insert(session)
        }
        session.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Workout" : title
        session.date = date
        session.sessionStart = sessionStart
        session.lastUpdated = now
        session.restEndsAt = restEndsAt
        if restEndsAt == nil {
            session.restStartedAt = nil
        } else if session.restStartedAt == nil {
            session.restStartedAt = now
        }

        session.sets.forEach(context.delete)
        session.sets = WorkoutInProgressEngine.persistedSets(from: exercises).map { draft in
            let set = WorkoutInProgressSet(
                exercise: draft.exercise,
                primaryMuscle: draft.primaryMuscle,
                exerciseOrder: draft.exerciseOrder,
                weight: draft.weight,
                reps: draft.reps,
                setNumber: draft.setNumber,
                isCompleted: draft.isCompleted,
                setType: draft.setType,
                rpe: draft.rpe
            )
            set.session = session
            context.insert(set)
            return set
        }
        do {
            try context.save()
        } catch {
            logger.error("Workout draft save failed")
            saveError = "Your unfinished workout could not be saved."
        }
    }

    private func startRestTimer() {
        let endsAt = Date.now.addingTimeInterval(TimeInterval(WorkoutInProgressEngine.defaultRestSeconds))
        restEndsAt = endsAt
        persistDraft()
    }

    private func discardDraft() {
        inProgressSessions.forEach(context.delete)
        do {
            try context.save()
            dismiss()
        } catch {
            logger.error("Workout draft discard failed")
            context.rollback()
            saveError = "Your unfinished workout could not be discarded."
        }
    }

    private func save() {
        let completedExercises = exercises.compactMap { exercise -> LoggedExercise? in
            let completedSets = exercise.sets.filter(\.isCompleted)
            guard !completedSets.isEmpty else { return nil }
            return LoggedExercise(name: exercise.name, primaryMuscle: exercise.primaryMuscle, sets: completedSets)
        }
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
                set.setTypeRaw = loggedSet.setType.rawValue
                set.rpe = RPEEngine.validated(loggedSet.rpe)
                set.workout = targetWorkout
                if loggedSet.existingModel == nil { context.insert(set) }
                finalSets.append(set)
            }
        }
        targetWorkout.sets = finalSets

        do {
            try context.save()
            if !isEditing {
                inProgressSessions.forEach(context.delete)
                try context.save()
            }
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
    let previous: PreviousSetPerformance?
    let weightUnit: WeightUnit
    let remove: () -> Void
    let startRest: () -> Void

    private var previousSummary: String? {
        guard let previous else { return nil }
        let sets = previous.sets.map { "\(Self.formatWeight($0.weight, unit: weightUnit)) \(weightUnit.symbol) × \($0.reps)" }.joined(separator: ", ")
        let age = RelativeDateTimeFormatter().localizedString(for: previous.date, relativeTo: .now)
        return "Last: \(sets) · \(age)"
    }

    private var previousTextColor: Color {
        previous?.isStale == true ? Color.secondary.opacity(0.55) : Color.secondary
    }

    static func formatWeight(_ weight: Double, unit: WeightUnit) -> String {
        unit.formatted(weight)
    }

    var body: some View {
        Section {
            ForEach($exercise.sets) { $set in
                let index = exercise.sets.firstIndex(where: { $0.id == set.id }) ?? 0
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                            .frame(minHeight: 44)
                            .accessibilityLabel("Set \(index + 1)")
                        NumericFieldDouble(value: Binding(
                            get: { weightUnit.fromKilograms(set.weight) },
                            set: { set.weight = max(0, weightUnit.toKilograms($0)) }
                        ), title: weightUnit.symbol)
                        NumericFieldInt(value: $set.reps, title: "reps")
                        TextField("RPE", value: $set.rpe, format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                            .frame(width: 56)
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Optional RPE for set \(index + 1)")
                        Button {
                            set.isCompleted.toggle()
                            if set.isCompleted { startRest() }
                        } label: {
                            Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(set.isCompleted ? .mint : .secondary)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(set.isCompleted ? "Mark set \(index + 1) incomplete" : "Mark set \(index + 1) complete")
                    }
                    Picker("Set type", selection: $set.setType) {
                        ForEach(SetType.allCases) { type in Text(type.rawValue).tag(type) }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Set \(index + 1) type")
                    if let previousSet = previous?.sets[safe: index] {
                        Text("Previous: \(Self.formatWeight(previousSet.weight, unit: weightUnit)) \(weightUnit.symbol) × \(previousSet.reps)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .accessibilityLabel("Previous performance: \(Self.formatWeight(previousSet.weight, unit: weightUnit)) \(weightUnit.symbol), \(previousSet.reps) reps")
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        exercise.sets.removeAll { $0.id == set.id }
                    } label: {
                        Label("Delete set", systemImage: "trash")
                    }
                }
            }
            Button {
                exercise.sets.append(WorkoutEditorLogic.nextSetDefaults(current: exercise.sets, previous: previous))
            } label: {
                Label("Add set", systemImage: "plus")
            }
        } header: {
            HStack {
                VStack(alignment: .leading) {
                    Text(exercise.name).font(.headline)
                    Text(exercise.primaryMuscle.rawValue).font(.caption).foregroundStyle(.secondary)
                    if let previousSummary {
                        Text(previousSummary).font(.caption).foregroundStyle(previousTextColor)
                    }
                }
                Spacer()
                Button(role: .destructive, action: remove) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Remove \(exercise.name)")
            }
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
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
