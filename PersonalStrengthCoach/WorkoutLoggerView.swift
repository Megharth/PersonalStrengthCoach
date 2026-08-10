import SwiftUI
import SwiftData
import OSLog

struct EditableSet: Identifiable, Hashable {
    let id = UUID()
    var weight: Double = 0
    var reps: Int = 8
}

struct LoggedExercise: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let primaryMuscle: MuscleGroup
    var sets: [EditableSet] = [EditableSet(), EditableSet(), EditableSet()]
}

struct WorkoutLoggerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var title = "Workout"
    @State private var date = Date.now
    @State private var sessionStart = Date.now
    @State private var exercises: [LoggedExercise] = []
    @State private var showingExercisePicker = false
    @State private var showingEmptyAlert = false
    @State private var saveError: String?
    private let logger = Logger(subsystem: "com.personalstrengthcoach.app", category: "Persistence")

    var body: some View {
        NavigationStack {
            List {
                Section("Workout") {
                    TextField("Workout name", text: $title)
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
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
            .navigationTitle("Log Workout")
            .navigationBarTitleDisplayMode(.inline)
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
            .alert("Add an exercise first", isPresented: $showingEmptyAlert) {
                Button("OK", role: .cancel) { }
            } message: { Text("A workout needs at least one exercise and one working set.") }
            .alert("Couldn’t save workout", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) { }
            } message: { Text(saveError ?? "Your workout was not saved. Try again.") }
        }
    }

    private func save() {
        let completedExercises = exercises.filter { !$0.sets.isEmpty }
        guard !completedExercises.isEmpty else { showingEmptyAlert = true; return }
        let workout = Workout(date: date, title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Workout" : title, durationMinutes: WorkoutTimerEngine.elapsedMinutes(start: sessionStart, end: .now))
        context.insert(workout)
        for exercise in completedExercises {
            for (index, loggedSet) in exercise.sets.enumerated() {
                let set = ExerciseSet(exercise: exercise.name, weight: loggedSet.weight, reps: loggedSet.reps, setNumber: index + 1, primaryMuscle: exercise.primaryMuscle)
                set.workout = workout
                context.insert(set)
            }
        }
        do {
            try context.save()
            dismiss()
        } catch {
            logger.error("Workout save failed")
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
