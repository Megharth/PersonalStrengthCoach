import SwiftUI
import SwiftData
import OSLog

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]
    @Query(sort: \DailyRecovery.date, order: .reverse) private var recoveryDays: [DailyRecovery]
    @State private var selectedTab = 0
    @State private var healthKitAlert: HealthKitAlert?
    private let logger = Logger(subsystem: "com.personalstrengthcoach.app", category: "HealthKit")

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(workouts: workouts, recoveryDays: recoveryDays).tabItem { Label("Today", systemImage: "house.fill") }.tag(0)
            DashboardView(workouts: workouts, recoveryDays: recoveryDays).tabItem { Label("Dashboard", systemImage: "chart.xyaxis.line") }.tag(1)
            WorkoutHistoryView(workouts: workouts).tabItem { Label("History", systemImage: "clock.arrow.circlepath") }.tag(2)
            RecoveryView(workouts: workouts, recoveryDays: recoveryDays).tabItem { Label("Recovery", systemImage: "heart.fill") }.tag(3)
            CoachView(workouts: workouts, recoveryDays: recoveryDays).tabItem { Label("Coach", systemImage: "sparkles") }.tag(4)
            DataManagementView().tabItem { Label("Settings", systemImage: "gearshape.fill") }.tag(5)
        }
        .tint(.mint)
        .task {
            #if DEBUG
            SeedData.loadIfNeeded(context: context, workouts: workouts)
            #endif
            await syncHealthKit()
        }
        .alert(healthKitAlert?.title ?? "Health data", isPresented: Binding(get: { healthKitAlert != nil }, set: { if !$0 { healthKitAlert = nil } })) {
            Button("Retry") { Task { await syncHealthKit() } }
            Button("Not now", role: .cancel) { }
        } message: { Text(healthKitAlert?.message ?? "Health data could not be refreshed.") }
    }

    private func syncHealthKit() async {
        let status = await HealthKitService.sync(context: context)
        switch status {
        case .unavailable, .notDetermined, .synced:
            healthKitAlert = nil
        case .noReadableData:
            healthKitAlert = HealthKitAlert(
                title: "No readable Health data",
                message: "No readable Apple Health recovery data yet. Check that Personal Strength Coach can read Sleep, Heart Rate, HRV, and Body Mass in the Health app."
            )
        case .failed(let message):
            logger.error("HealthKit sync failed: \(message, privacy: .public)")
            healthKitAlert = HealthKitAlert(title: "Couldn’t sync Health data", message: "Check Health permissions and try again.")
        }
    }
}

private struct HealthKitAlert {
    let title: String
    let message: String
}

struct HomeView: View {
    let workouts: [Workout]; let recoveryDays: [DailyRecovery]
    var body: some View {
        let result = RecoveryEngine.readiness(today: recoveryDays.first, recent: recoveryDays, workouts: workouts)
        let recommendation = RecommendationEngine.nextWorkout(workouts: workouts)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Good morning").font(.largeTitle.bold())
                    Text(Date.now.formatted(.dateTime.weekday(.wide).month().day())).foregroundStyle(.secondary)
                    ReadinessCard(result: result)
                    HStack(spacing: 12) {
                        MetricCard(title: "Sleep", value: String(format: "%.1f", recoveryDays.first?.sleepHours ?? 0), unit: "hours", icon: "bed.double.fill", tint: .indigo)
                        MetricCard(title: "HRV", value: String(Int(recoveryDays.first?.hrv ?? 0)), unit: "ms", icon: "waveform.path.ecg", tint: .pink)
                        MetricCard(title: "Resting HR", value: String(Int(recoveryDays.first?.restingHeartRate ?? 0)), unit: "bpm", icon: "heart.fill", tint: .red)
                    }
                    SectionTitle("Recommended today")
                    CoachCard(title: recommendation.title, detail: recommendation.detail, icon: "figure.strengthtraining.traditional")
                    SectionTitle("Coach summary")
                    if result.confidence == .low {
                        let detail = result.factors.count == 1
                            ? result.factors[0]
                            : "Keep syncing Apple Health to build a reliable baseline. \(result.factors.joined(separator: " · "))"
                        CoachCard(
                            title: result.factors.count == 1 ? "Readiness data needed" : "Building your readiness baseline",
                            detail: detail,
                            icon: "sparkles"
                        )
                    } else {
                        CoachCard(
                            title: result.score >= 75 ? "Set up for a strong session" : result.score >= 55 ? "Train with steady intent" : "Prioritize recovery today",
                            detail: "\(result.factors.joined(separator: " · ")). Suggested focus: \(recommendation.title) — \(recommendation.detail)",
                            icon: "sparkles"
                        )
                    }
                }.padding()
            }.background(Color(uiColor: .systemGroupedBackground)).navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct DashboardView: View {
    let workouts: [Workout]; let recoveryDays: [DailyRecovery]
    @AppStorage("weightUnit") private var weightUnitRawValue = WeightUnit.defaultUnit.rawValue
    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRawValue) ?? .defaultUnit }
    var body: some View {
        let strengthTrend = PerformanceEngine.strengthTrend(in: workouts)
        NavigationStack { ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Dashboard").font(.largeTitle.bold())
                let weeklyVolume = PerformanceEngine.weeklyVolume(workouts)
                HStack { MetricCard(title: "Weekly Volume", value: weightUnit.formattedThousands(weeklyVolume) + "k", unit: weightUnit.symbol, icon: "dumbbell.fill", tint: .orange); MetricCard(title: "Workouts", value: "\(workouts.filter { $0.date > .now.addingTimeInterval(-604800) }.count)", unit: "this week", icon: "calendar", tint: .mint) }
                if let strengthTrend {
                    TrendChart(title: "Strength trend (\(strengthTrend.exercise) est. 1RM)", points: strengthTrend.points, tint: .mint)
                } else {
                    ContentUnavailableView(
                        "Strength trend unavailable",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Log the same weighted exercise in at least two weeks to compare estimated 1RM.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 130)
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                }
                TrendChart(title: "Sleep trend", points: recoveryDays.prefix(7).reversed().map { $0.sleepHours }, tint: .indigo)
                TrendChart(title: "HRV trend", points: recoveryDays.prefix(7).reversed().map(\.hrv), tint: .pink)
            }.padding()
        }.background(Color(uiColor: .systemGroupedBackground)) }
    }
}

struct WorkoutHistoryView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("weightUnit") private var weightUnitRawValue = WeightUnit.defaultUnit.rawValue
    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRawValue) ?? .defaultUnit }
    let workouts: [Workout]
    @Query(sort: \WorkoutInProgress.lastUpdated, order: .reverse) private var inProgressSessions: [WorkoutInProgress]
    @State private var showingLogger = false
    @State private var showingStartConfirmation = false
    @State private var workoutPendingDeletion: Workout?
    @State private var errorMessage: String?
    private let logger = Logger(subsystem: "com.personalstrengthcoach.app", category: "Persistence")

    private var activeDraft: WorkoutInProgress? { inProgressSessions.first }

    var body: some View { NavigationStack { List {
        if let draft = activeDraft {
            Section("Unfinished workout") {
                Button { showingLogger = true } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .foregroundStyle(.mint)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Resume \(draft.title)")
                                .font(.headline)
                            Text("Started \(draft.sessionStart.formatted(date: .abbreviated, time: .shortened))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
            }
        }

        if workouts.isEmpty {
            ContentUnavailableView("No workouts yet", systemImage: "dumbbell.fill", description: Text("Log your first session from the + menu to start tracking volume, PRs, and recovery."))
                .listRowBackground(Color.clear)
        } else {
        ForEach(workouts) { workout in NavigationLink { WorkoutDetailView(workout: workout, history: workouts) } label: {
            HStack { Image(systemName: "dumbbell.fill").foregroundStyle(.mint).frame(width: 30); VStack(alignment: .leading) { Text(workout.title).font(.headline); Text(workout.date.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary) }; Spacer(); VStack(alignment: .trailing) { Text(weightUnit.formattedWithUnit(workout.volume, fractionDigits: 0)).font(.subheadline.weight(.semibold)); Text("\(workout.durationMinutes) min").font(.caption).foregroundStyle(.secondary) } }
        } }
        // Swipe arms the confirmation rather than deleting outright — this is
        // unrecoverable and `.onDelete` has no built-in confirmation.
        .onDelete { offsets in
            workoutPendingDeletion = offsets.compactMap { workouts.indices.contains($0) ? workouts[$0] : nil }.first
        }
        }
        }
        .navigationTitle("Workout History")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { startNewWorkoutTapped() } label: { Label("Log workout", systemImage: "plus.circle") }
                    NavigationLink { RoutinesListView() } label: { Label("Routines", systemImage: "list.bullet.rectangle") }
                    NavigationLink { StrongImportView() } label: { Label("Import from Strong", systemImage: "square.and.arrow.down") }
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingLogger) { WorkoutLoggerView() }
        .confirmationDialog("Resume unfinished workout?", isPresented: $showingStartConfirmation, titleVisibility: .visible) {
            Button("Resume Workout") { showingLogger = true }
            Button("Discard and Start New", role: .destructive) { discardDraftThenStartNew() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have an unfinished workout in progress. Resume it, or discard it to start a new one.")
        }
        .confirmationDialog("Delete workout?", isPresented: Binding(get: { workoutPendingDeletion != nil }, set: { if !$0 { workoutPendingDeletion = nil } }), titleVisibility: .visible) {
            Button("Delete Workout", role: .destructive) {
                if let workout = workoutPendingDeletion { delete(workout) }
                workoutPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { workoutPendingDeletion = nil }
        } message: { Text("This permanently removes the session and all of its sets. This can’t be undone.") }
        .alert("Couldn’t update workouts", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { }
        } message: { Text(errorMessage ?? "Please try again.") }
    } }

    private func startNewWorkoutTapped() {
        if activeDraft == nil {
            showingLogger = true
        } else {
            showingStartConfirmation = true
        }
    }

    private func discardDraftThenStartNew() {
        inProgressSessions.forEach(context.delete)
        do {
            try context.save()
            showingLogger = true
        } catch {
            logger.error("Workout draft replacement failed")
            context.rollback()
            errorMessage = "The unfinished workout could not be discarded."
        }
    }

    private func delete(_ workout: Workout) {
        context.delete(workout)     // cascade removes its ExerciseSet rows
        do {
            try context.save()
        } catch {
            logger.error("Workout delete failed")
            context.rollback()
            errorMessage = "The workout could not be deleted."
        }
    }
}

struct WorkoutDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("weightUnit") private var weightUnitRawValue = WeightUnit.defaultUnit.rawValue
    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRawValue) ?? .defaultUnit }
    let workout: Workout; let history: [Workout]
    @State private var showingEditor = false
    @State private var showingDeleteConfirmation = false
    @State private var deleteError: String?
    private let logger = Logger(subsystem: "com.personalstrengthcoach.app", category: "Persistence")
    private var groupedExercises: [(name: String, sets: [ExerciseSet])] {
        Dictionary(grouping: workout.sets, by: \.normalizedExercise)
            .map { (name: $0.key, sets: $0.value) }
            .sorted { $0.name < $1.name }
    }
    var body: some View { List {
        Section("Session") { LabeledContent("Volume", value: weightUnit.formattedWithUnit(workout.volume, fractionDigits: 0)); LabeledContent("Duration", value: "\(workout.durationMinutes) min"); LabeledContent("Calories", value: "\(workout.calories) kcal") }
        Section("Exercises") {
            ForEach(groupedExercises, id: \.name) { exercise in
                ExerciseRow(name: exercise.name, sets: exercise.sets, allSets: history.flatMap(\.sets))
            }
        }
        let records = PerformanceEngine.personalRecords(in: workout, history: history)
        if !records.isEmpty { Section("Personal records") { ForEach(records, id: \.self) { Label($0, systemImage: "trophy.fill").foregroundStyle(.yellow) } } }
        Section("Coach notes") {
            if !records.isEmpty {
                Text("Outstanding effort — achieved PRs in \(records.joined(separator: ", ")). Maintain steady recovery before your next heavy session.")
            } else if workout.volume > 8_000 {
                Text("High-volume session completed (\(weightUnit.formattedWithUnit(workout.volume, fractionDigits: 0))). Focus on adequate protein intake and sleep tonight.")
            } else {
                Text("Solid training session (\(workout.sets.count) sets). Keep your compounds controlled and preserve clean technique.")
            }
        }
        Section {
            Button("Delete Workout", role: .destructive) { showingDeleteConfirmation = true }
        }
    }
    .navigationTitle(workout.title).navigationBarTitleDisplayMode(.inline)
    .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showingEditor = true } label: { Label("Edit Workout", systemImage: "pencil") }
        }
    }
    // WorkoutLoggerView owns its own NavigationStack, so present it bare.
    .sheet(isPresented: $showingEditor) { WorkoutLoggerView(workout: workout) }
    .confirmationDialog("Delete workout?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
        Button("Delete Workout", role: .destructive) { deleteWorkout() }
        Button("Cancel", role: .cancel) { }
    } message: { Text("This permanently removes the session and all of its sets. This can’t be undone.") }
    .alert("Couldn’t delete workout", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
        Button("OK", role: .cancel) { }
    } message: { Text(deleteError ?? "Please try again.") }
    }

    private func deleteWorkout() {
        context.delete(workout)     // cascade removes its ExerciseSet rows
        do {
            try context.save()
            dismiss()
        } catch {
            logger.error("Workout delete failed")
            context.rollback()
            deleteError = "The workout could not be deleted."
        }
    }
}

private struct ExerciseRow: View {
    @AppStorage("weightUnit") private var weightUnitRawValue = WeightUnit.defaultUnit.rawValue
    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRawValue) ?? .defaultUnit }
    let name: String
    let sets: [ExerciseSet]
    let allSets: [ExerciseSet]
    private var volume: Double { sets.reduce(0) { total, set in
        guard set.setType != .warmup else { return total }
        return total + set.weight * Double(set.reps)
    } }

    private var metadataSummary: String {
        sets.map { set in
            var details = set.setType.rawValue
            if let rpe = set.rpe { details += " · RPE \(String(format: "%.1f", rpe))" }
            return details
        }.joined(separator: " · ")
    }
    var body: some View {
        NavigationLink {
            ExerciseDetailView(exercise: name, sets: allSets)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                Text("\(sets.count) sets · \(weightUnit.formattedWithUnit(volume, fractionDigits: 0))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(metadataSummary)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }
}
