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

    /// Rebuilds editable exercise blocks from a workout's unordered `sets`
    /// relationship. Blocks remain keyed on the raw `exercise` string (never
    /// `normalizedExercise`, which would rename the user's entry), and use the
    /// persisted exercise-block order when available. Legacy rows without an
    /// order follow a deterministic alphabetical fallback.
    static func editableExercises(from sets: [ExerciseSet]) -> [LoggedExercise] {
        Dictionary(grouping: sets, by: \.exercise)
            .sorted { lhs, rhs in
                let lhsOrder = lhs.value.compactMap(\.exerciseOrder).min()
                let rhsOrder = rhs.value.compactMap(\.exerciseOrder).min()
                switch (lhsOrder, rhsOrder) {
                case let (left?, right?) where left != right: return left < right
                case (_?, nil): return true
                case (nil, _?): return false
                default: return lhs.key < rhs.key
                }
            }
            .map { name, group in
                let ordered = group.sorted { ($0.setNumber, $0.weight, $0.reps) < ($1.setNumber, $1.weight, $1.reps) }
                return LoggedExercise(name: name, primaryMuscle: ordered.first?.primaryMuscle ?? .core, sets: ordered.map(EditableSet.init(model:)))
            }
    }
}

struct WorkoutLoggerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Workout.date, order: .reverse) private var allWorkouts: [Workout]
    @Query(sort: \WorkoutInProgress.lastUpdated, order: .reverse) private var inProgressSessions: [WorkoutInProgress]
    let workout: Workout?          // nil == log a new workout
    let startingRoutine: Routine?  // pre-fill from Routines tab when logging a new workout
    @State private var title = "Workout"
    @State private var sessionStart = Date.now
    @State private var durationMinutes = 0
    @State private var exercises: [LoggedExercise] = []
    @State private var hasLoadedDraft = false
    @State private var showingExercisePicker = false
    @State private var routinePendingReplacement: Routine?
    @State private var showingRoutineReplacementConfirmation = false
    @State private var showingEmptyAlert = false
    @State private var saveError: String?
    @State private var restEndsAt: Date?
    @State private var now = Date.now
    @State private var showingDiscardConfirmation = false
    @State private var showingSyncBiometrics = false
    @State private var savedWorkoutStart: Date?
    @State private var savedWorkoutEnd: Date?
    @StateObject private var hkService = WorkoutHealthKitService()
    @AppStorage("weightUnit") private var weightUnitRawValue = WeightUnit.defaultUnit.rawValue
    private let logger = Logger(subsystem: "com.personalstrengthcoach.app", category: "Persistence")

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRawValue) ?? .defaultUnit }
    private var exerciseListAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.28)
    }

    // Explicit init so `WorkoutLoggerView()` still resolves once `workout` is a
    // stored non-defaulted property: adding it removes the synthesized default init,
    // and the memberwise one is private (the `@State` are), so it can't be seen
    // from `RootView`.
    init(workout: Workout? = nil, startingRoutine: Routine? = nil) {
        self.workout = workout
        self.startingRoutine = startingRoutine
    }

    private var isEditing: Bool { workout != nil }

    var body: some View {
        NavigationStack {
            loggerList
        }
    }

    private var loggerList: some View {
        List {
            Section("Workout") {
                TextField("Workout name", text: $title)
                if isEditing {
                    Stepper("Duration: \(durationMinutes) min", value: $durationMinutes, in: 1...240)
                }
            }

            if exercises.isEmpty {
                ContentUnavailableView("Add your first exercise", systemImage: "dumbbell.fill", description: Text("Choose from the exercise library or create your own."))
                    .listRowBackground(Color.clear)
            }

            ForEach($exercises) { $exercise in
                exerciseRow(for: $exercise)
            }

            Section {
                Button { showingExercisePicker = true } label: {
                    Label("Add exercise", systemImage: "plus.circle.fill")
                        .fontWeight(.semibold)
                }
                .accessibilityIdentifier("addExerciseButton")
            }
        }
        // Docked via safeAreaInset rather than a trailing List section: a
        // stat a set is actively being logged against (Rest, above all)
        // needs to stay visible regardless of scroll position or which
        // set row is expanded, not scroll away below the exercise list.
        .safeAreaInset(edge: .top) {
            sessionStatsInset
        }
        .navigationTitle(isEditing ? "Edit Workout" : "Log Workout")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadDraftIfNeeded)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { persistDraft() }
        }
        .onChange(of: title) { _, _ in persistDraft() }
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
                let previous = previousPerformance(for: exercise.name)
                withAnimation(exerciseListAnimation) {
                    exercises.append(LoggedExercise.draftExercise(from: exercise, previous: previous))
                }
                showingExercisePicker = false
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
        .sheet(isPresented: $showingSyncBiometrics, onDismiss: {
            Task { await hkService.finishIfNeeded(at: savedWorkoutEnd ?? .now) }
            dismiss()
        }) {
            if let start = savedWorkoutStart, let end = savedWorkoutEnd {
                SyncBiometricsView(hkService: hkService, workoutStart: start, workoutEnd: end)
            }
        }
    }

    @ViewBuilder
    private var sessionStatsInset: some View {
        if !isEditing {
            let sessionVolume = WorkoutInProgressEngine.volume(of: exercises)
            let elapsedMinutes = WorkoutInProgressEngine.elapsedSeconds(start: sessionStart, now: now) / 60
            let restLabel = WorkoutInProgressEngine.formattedRest(endsAt: restEndsAt, now: now)

            SessionStatsStrip(
                volume: weightUnit.formattedWithUnit(sessionVolume, fractionDigits: 0),
                elapsed: "\(elapsedMinutes) min",
                rest: restLabel
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            .animation(reduceMotion ? .easeInOut(duration: 0.15) : .easeInOut(duration: 0.25), value: restEndsAt != nil)
        }
    }

    @ViewBuilder
    private func exerciseRow(for exercise: Binding<LoggedExercise>) -> some View {
        let exerciseID = exercise.wrappedValue.id
        ExerciseLoggerCard(
            exercise: exercise,
            previous: previousPerformance(for: exercise.wrappedValue.name),
            weightUnit: weightUnit,
            reduceMotion: reduceMotion,
            remove: { removeExercise(id: exerciseID) },
            startRest: startRestTimer
        )
        .transition(exerciseCardTransition)
        .id(exerciseID)
    }

    private var exerciseCardTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
        )
    }

    private func previousPerformance(for exerciseName: String) -> PreviousSetPerformance? {
        PreviousSetEngine.mostRecentPerformance(
            for: exerciseName,
            in: allWorkouts,
            excluding: workout
        )
    }

    private func removeExercise(id: LoggedExercise.ID) {
        withAnimation(exerciseListAnimation) {
            exercises.removeAll { $0.id == id }
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
            sessionStart = workout.date
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

        if let session = resolved.current {
            title = session.title
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
        } else {
            persistDraft()
        }

        let start = sessionStart
        Task { await hkService.startWorkout(at: start) }

        if let startingRoutine {
            if exercises.isEmpty {
                applyRoutine(startingRoutine)
            } else {
                routinePendingReplacement = startingRoutine
                showingRoutineReplacementConfirmation = true
            }
        }
    }

    private func persistDraft() {
        guard hasLoadedDraft, !isEditing else { return }
        let now = Date.now
        let session: WorkoutInProgress
        if let existing = inProgressSessions.first {
            session = existing
        } else {
            session = WorkoutInProgress(title: title, date: sessionStart, sessionStart: sessionStart, lastUpdated: now)
            context.insert(session)
        }
        session.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Workout" : title
        session.date = sessionStart
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
        hkService.discardWorkout()
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
        let targetWorkout = workout ?? Workout(date: sessionStart, title: resolvedTitle, durationMinutes: WorkoutTimerEngine.elapsedMinutes(start: sessionStart, end: .now))
        if workout == nil { context.insert(targetWorkout) }
        targetWorkout.date = sessionStart
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
        for (exerciseIndex, exercise) in completedExercises.enumerated() {
            for (index, loggedSet) in exercise.sets.enumerated() {
                let set = loggedSet.existingModel ?? ExerciseSet(exercise: exercise.name, weight: loggedSet.weight, reps: loggedSet.reps, setNumber: index + 1, exerciseOrder: exerciseIndex, primaryMuscle: exercise.primaryMuscle)
                set.weight = loggedSet.weight
                set.reps = loggedSet.reps
                set.setNumber = index + 1
                set.exerciseOrder = exerciseIndex
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
                savedWorkoutStart = sessionStart
                savedWorkoutEnd = Date.now
                showingSyncBiometrics = true
            } else {
                dismiss()
            }
        } catch {
            logger.error("Workout save failed")
            context.rollback()
            saveError = "Your workout was not saved. Try again."
        }
    }
}

/// Volume/Elapsed/Rest as equal-width cells in one hairline-divided strip,
/// matching the "Expandable Card" mockup's stat-strip pattern.
private struct SessionStatsStrip: View {
    let volume: String
    let elapsed: String
    let rest: String?

    var body: some View {
        HStack(spacing: 1) {
            StatStripCell(label: "Volume", value: volume)
            StatStripCell(label: "Elapsed", value: elapsed)
            if let rest {
                StatStripCell(label: "Rest", value: rest, valueColor: .mint)
            }
        }
        .background(Color(uiColor: .separator))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sessionStatsStrip")
    }
}

private struct StatStripCell: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.2).foregroundStyle(.secondary)
            Text(value).font(.system(size: 17, weight: .bold)).foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("statStripCell-\(label)")
        .accessibilityLabel("\(label) \(value)")
    }
}

/// Set rows behave as an accordion: only one set per exercise is fully open for
/// editing at a time (`expandedSetID`), the rest collapse to a single scannable
/// line. This keeps a workout with several sets from turning into a wall of
/// simultaneously-editable text fields.
private struct ExerciseLoggerCard: View {
    @Binding var exercise: LoggedExercise
    let previous: PreviousSetPerformance?
    let weightUnit: WeightUnit
    let reduceMotion: Bool
    let remove: () -> Void
    let startRest: () -> Void
    @State private var expandedSetID: EditableSet.ID?

    init(
        exercise: Binding<LoggedExercise>,
        previous: PreviousSetPerformance?,
        weightUnit: WeightUnit,
        reduceMotion: Bool,
        remove: @escaping () -> Void,
        startRest: @escaping () -> Void
    ) {
        self._exercise = exercise
        self.previous = previous
        self.weightUnit = weightUnit
        self.reduceMotion = reduceMotion
        self.remove = remove
        self.startRest = startRest
        self._expandedSetID = State(initialValue: exercise.wrappedValue.sets.first { !$0.isCompleted }?.id)
    }

    var body: some View {
        Section {
            ForEach($exercise.sets) { $set in
                let index = exercise.sets.firstIndex(where: { $0.id == set.id }) ?? 0
                if expandedSetID == set.id {
                    ExpandedSetRow(
                        set: $set,
                        index: index,
                        weightUnit: weightUnit,
                        previousSet: previous?.sets[safe: index],
                        collapse: { updateExpandedSet(nil) },
                        markDone: { markDone(id: set.id) }
                    )
                    .transition(setRowTransition)
                } else {
                    CollapsedSetRow(set: set, index: index, weightUnit: weightUnit) {
                        updateExpandedSet(set.id)
                    }
                    .transition(setRowTransition)
                }
            }
            .onDelete { offsets in
                let removedIDs = Set(offsets.map { exercise.sets[$0].id })
                exercise.sets.remove(atOffsets: offsets)
                if let expandedSetID, removedIDs.contains(expandedSetID) {
                    self.expandedSetID = nil
                }
            }
            Button {
                let newSet = EditableSet()
                withAnimation(setRowAnimation) {
                    exercise.sets.append(newSet)
                    expandedSetID = newSet.id
                }
            } label: { Label("Add set", systemImage: "plus") }
        } header: {
            HStack {
                VStack(alignment: .leading) {
                    Text(exercise.name).font(.headline)
                    Text(exercise.primaryMuscle.rawValue).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive, action: remove) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove exercise")
            }
        }
    }

    /// Toggles completion; when a set is newly completed, starts the rest timer
    /// and hands the accordion off to the next incomplete set so a linear
    /// logging session doesn't need a manual tap to open the next row.
    private func markDone(id: EditableSet.ID) {
        guard let setIndex = exercise.sets.firstIndex(where: { $0.id == id }) else { return }
        let willComplete = !exercise.sets[setIndex].isCompleted
        withAnimation(setRowAnimation) {
            exercise.sets[setIndex].isCompleted = willComplete
            guard willComplete else { return }
            expandedSetID = exercise.sets[(setIndex + 1)...].first { !$0.isCompleted }?.id
        }
        guard willComplete else { return }
        startRest()
    }

    private var setRowAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.24)
    }

    private var setRowTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
    }

    private func updateExpandedSet(_ id: EditableSet.ID?) {
        withAnimation(setRowAnimation) {
            expandedSetID = id
        }
    }
}

private struct CollapsedSetRow: View {
    let set: EditableSet
    let index: Int
    let weightUnit: WeightUnit
    let expand: () -> Void

    var body: some View {
        Button(action: expand) {
            HStack(spacing: 12) {
                Text("\(index + 1)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color(.tertiarySystemFill)))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(weightUnit.formatted(set.weight)) \(weightUnit.symbol) × \(set.reps)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(set.setType.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if set.isCompleted {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set \(index + 1), \(weightUnit.formatted(set.weight)) \(weightUnit.symbol) by \(set.reps) reps, \(set.setType.rawValue), \(set.isCompleted ? "completed" : "not completed")")
        .accessibilityHint("Double tap to edit this set")
        .accessibilityIdentifier("setRow-\(index)")
    }
}

private enum SetInputField: Hashable {
    case weight
    case reps
}

private struct ExpandedSetRow: View {
    @Binding var set: EditableSet
    let index: Int
    let weightUnit: WeightUnit
    let previousSet: ExerciseSet?
    let collapse: () -> Void
    let markDone: () -> Void
    @FocusState private var focusedField: SetInputField?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Set \(index + 1)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.mint)
                Spacer()
                Button(action: collapse) {
                    Image(systemName: "chevron.up").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Collapse set \(index + 1)")
            }

            if let previousSet {
                PreviousSetReferenceBanner(previousSet: previousSet, weightUnit: weightUnit, index: index) {
                    set.weight = previousSet.weight
                    set.reps = previousSet.reps
                }
            }

            HStack(spacing: 12) {
                WeightInputField(weightKg: $set.weight, unit: weightUnit, focusedField: $focusedField, index: index)
                RepsInputField(reps: $set.reps, focusedField: $focusedField, index: index)
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }

            Picker("Set type", selection: $set.setType) {
                ForEach(SetType.allCases) { type in Text(type.rawValue).tag(type) }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Set type")

            HStack {
                Text("RPE").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                RPEStepperControl(rpe: $set.rpe)
            }

            Button(action: markDone) {
                Label(set.isCompleted ? "Completed" : "Mark Complete", systemImage: set.isCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.mint)
            .accessibilityIdentifier("markCompleteButton-\(index)")
        }
        .padding(.vertical, 6)
    }
}

/// Surfaces the prior session's weight/reps for this set right beside the
/// fields being edited, so the reference is visible at the moment it's
/// actionable instead of buried below the RPE control.
private struct PreviousSetReferenceBanner: View {
    let previousSet: ExerciseSet
    let weightUnit: WeightUnit
    let index: Int
    let useAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.mint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("LAST TIME")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.mint)
                    Text("\(weightUnit.formatted(previousSet.weight)) \(weightUnit.symbol) × \(previousSet.reps)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Last time \(weightUnit.formatted(previousSet.weight)) \(weightUnit.symbol) by \(previousSet.reps) reps")
            Spacer()
            Button("Use", action: useAction)
                .buttonStyle(.borderedProminent)
                .tint(.mint)
                .controlSize(.small)
                .accessibilityIdentifier("usePreviousSetButton-\(index)")
        }
        .padding(10)
        .background(Color.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.mint.opacity(0.35), lineWidth: 1))
    }
}

private struct WeightInputField: View {
    @Binding var weightKg: Double
    let unit: WeightUnit
    var focusedField: FocusState<SetInputField?>.Binding
    let index: Int
    @State private var text = ""
    @State private var lastSyncedWeightKg: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Weight").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                TextField("0", text: $text, onEditingChanged: { isEditing in
                    if !isEditing { commitWeight() }
                }, onCommit: commitWeight)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .focused(focusedField, equals: .weight)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("weightField-\(index)")
                .onAppear {
                    text = unit.formatted(weightKg)
                    lastSyncedWeightKg = weightKg
                }
                .onChange(of: text) { _, _ in
                    // Keep the model current while the field is focused. Save and
                    // Mark Complete can run before SwiftUI delivers a focus-loss
                    // callback, so blur-only commits can lose the latest value.
                    commitWeight()
                }
                .onChange(of: weightKg) { _, newValue in
                    // A model change equal to the value just parsed came from this
                    // field. Other changes (for example, Previous Set's Use button)
                    // must still refresh the visible text.
                    guard lastSyncedWeightKg != newValue else { return }
                    text = unit.formatted(newValue)
                    lastSyncedWeightKg = newValue
                }
                Text(unit.symbol).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RepsInputField: View {
    @Binding var reps: Int
    var focusedField: FocusState<SetInputField?>.Binding
    let index: Int
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reps").font(.caption).foregroundStyle(.secondary)
            TextField("0", text: $text)
                .onChange(of: text) { _, newText in
                    if newText.isEmpty {
                        reps = 1
                    } else if let value = Int(newText) {
                        reps = max(1, value)
                    }
                }
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .focused(focusedField, equals: .reps)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityIdentifier("repsField-\(index)")
            .onAppear { text = String(reps) }
            .onChange(of: reps) { _, newValue in
                if Int(text) != newValue {
                    text = String(newValue)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RPEStepperControl: View {
    @Binding var rpe: Double?

    var body: some View {
        HStack(spacing: 16) {
            Button { decrement() } label: { Image(systemName: "minus.circle.fill") }
                .disabled(rpe == nil)
            Text(rpe.map { String(format: "%.1f", $0) } ?? "—")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 30)
            Button { increment() } label: { Image(systemName: "plus.circle.fill") }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.mint)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("RPE")
        .accessibilityValue(rpe.map { String(format: "%.1f", $0) } ?? "Not set")
    }

    private func increment() { rpe = RPEEngine.validated((rpe ?? 5.5) + 0.5) }
    private func decrement() {
        guard let current = rpe else { return }
        rpe = RPEEngine.validated(current - 0.5)
    }
}

private extension WeightInputField {
    func commitWeight() {
        let newWeightKg: Double
        if text.isEmpty {
            newWeightKg = 0
        } else if let value = Double(text) {
            newWeightKg = max(0, unit.toKilograms(value))
        } else {
            return
        }
        lastSyncedWeightKg = newWeightKg
        weightKg = newWeightKg
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
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

struct SyncBiometricsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var hkService: WorkoutHealthKitService
    let workoutStart: Date
    let workoutEnd: Date
    @State private var dayWorkouts: [WorkoutHealthKitService.HKWorkoutSummary] = []
    @State private var selectedWorkoutID: UUID?
    @State private var isFetchingWorkouts = false
    @State private var fetchError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.mint)

                VStack(spacing: 8) {
                    Text("Sync Biometrics")
                        .font(.title2.weight(.bold))
                    Text("After your wearable app has synced to Apple Health, choose which workout to attach heart rate and HRV from.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                if WorkoutHealthKitService.requiresManualSelection(among: dayWorkouts) {
                    VStack(spacing: 12) {
                        Text("Choose the matching workout")
                            .font(.headline)
                        ForEach(dayWorkouts) { summary in
                            workoutRow(summary)
                        }
                    }
                    .padding(.horizontal)
                }

                if let fetchError {
                    Text("Couldn't load workouts: \(fetchError)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                syncStateView

                Spacer()

                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
                    .padding(.bottom)
                    .accessibilityIdentifier("syncBiometricsDoneButton")
            }
            .accessibilityIdentifier("syncBiometricsView")
            .navigationTitle("Workout Saved")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("syncBiometricsToolbarDoneButton")
                }
            }
            .task { await fetchDayWorkouts() }
        }
    }

    private func workoutRow(_ summary: WorkoutHealthKitService.HKWorkoutSummary) -> some View {
        Button {
            selectedWorkoutID = summary.uuid
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selectedWorkoutID == summary.uuid ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedWorkoutID == summary.uuid ? .mint : .secondary)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(summary.activityName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(summary.sourceName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(summary.startDate.formatted(date: .omitted, time: .shortened)) – \(summary.endDate.formatted(date: .omitted, time: .shortened))  ·  \(summary.durationMinutes) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selectedWorkoutID == summary.uuid ? Color.mint : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("syncWorkoutOption-\(summary.uuid.uuidString)")
    }

    private func fetchDayWorkouts() async {
        guard !isFetchingWorkouts else { return }
        isFetchingWorkouts = true
        fetchError = nil
        do {
            dayWorkouts = try await WorkoutHealthKitService.workoutsForDay(workoutStart)
            selectedWorkoutID = WorkoutHealthKitService.defaultSelection(among: dayWorkouts)
        } catch {
            fetchError = error.localizedDescription
        }
        isFetchingWorkouts = false
    }

    @ViewBuilder
    private var syncStateView: some View {
        switch hkService.syncState {
        case .idle:
            Button {
                let chosenWorkout = dayWorkouts.first { $0.uuid == selectedWorkoutID }
                Task { await hkService.syncBiometrics(from: workoutStart, to: workoutEnd, linking: chosenWorkout) }
            } label: {
                Label("Sync from Apple Health", systemImage: "arrow.trianglehead.2.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.mint)
            .padding(.horizontal)
            .accessibilityIdentifier("syncFromHealthButton")

        case .syncing:
            ProgressView("Syncing…")
                .tint(.mint)

        case .synced(let hrCount, let hrvCount):
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.mint)
                if hrCount == 0 && hrvCount == 0 {
                    Text("No heart rate or HRV samples found yet. Open your wearable app to sync, then try again.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else {
                    Text("Attached \(hrCount) heart rate and \(hrvCount) HRV samples")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("syncBiometricsSuccessMessage")

        case .failed(let message):
            VStack(spacing: 12) {
                Text("Sync failed: \(message)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button {
                    let chosenWorkout = dayWorkouts.first { $0.uuid == selectedWorkoutID }
                    Task { await hkService.syncBiometrics(from: workoutStart, to: workoutEnd, linking: chosenWorkout) }
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.mint)
                .padding(.horizontal)
                .accessibilityIdentifier("tryAgainSyncButton")
            }

        case .unavailable:
            Text("Apple Health is not available on this device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
