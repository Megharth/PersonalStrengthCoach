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
            WorkoutsView(workouts: workouts).tabItem { Label("Workouts", systemImage: "dumbbell.fill") }.tag(2)
            RecoveryView(workouts: workouts, recoveryDays: recoveryDays).tabItem { Label("Recovery", systemImage: "heart.fill") }.tag(3)
            CoachView(workouts: workouts, recoveryDays: recoveryDays).tabItem { Label("Coach", systemImage: "sparkles") }.tag(4)
            DataManagementView().tabItem { Label("Settings", systemImage: "gearshape.fill") }.tag(5)
        }
        .tint(.mint)
        .task {
            #if DEBUG
            SeedData.loadIfNeeded(context: context, workouts: workouts)
            #endif
            guard !ProcessInfo.processInfo.arguments.contains("-uitesting") else { return }
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

struct WorkoutsView: View {
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
        ForEach(Array(workouts.enumerated()), id: \.element.id) { index, workout in NavigationLink { WorkoutDetailView(workout: workout, history: workouts) } label: {
            HStack { Image(systemName: "dumbbell.fill").foregroundStyle(.mint).frame(width: 30); VStack(alignment: .leading) { Text(workout.title).font(.headline); Text(workout.date.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary) }; Spacer(); VStack(alignment: .trailing) { Text(weightUnit.formattedWithUnit(workout.volume, fractionDigits: 0)).font(.subheadline.weight(.semibold)); Text("\(workout.durationMinutes) min").font(.caption).foregroundStyle(.secondary) } }
        }
        .accessibilityIdentifier("workoutRow-\(index)") }
        // Swipe arms the confirmation rather than deleting outright — this is
        // unrecoverable and `.onDelete` has no built-in confirmation.
        .onDelete { offsets in
            workoutPendingDeletion = offsets.compactMap { workouts.indices.contains($0) ? workouts[$0] : nil }.first
        }
        }
        }
        .navigationTitle("Workouts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { startNewWorkoutTapped() } label: { Label("Log workout", systemImage: "plus.circle") }
                        .accessibilityIdentifier("logWorkoutMenuItem")
                    NavigationLink { RoutinesListView() } label: { Label("Routines", systemImage: "list.bullet.rectangle") }
                        .accessibilityIdentifier("routinesMenuItem")
                    NavigationLink { StrongImportView() } label: { Label("Import from Strong", systemImage: "square.and.arrow.down") }
                } label: { Image(systemName: "plus") }
                .accessibilityIdentifier("addWorkoutMenuButton")
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
    private var orderedSets: [ExerciseSet] {
        workout.sets.sorted { lhs, rhs in
            let lhsOrder = lhs.exerciseOrder
            let rhsOrder = rhs.exerciseOrder
            switch (lhsOrder, rhsOrder) {
            case let (left?, right?) where left != right: return left < right
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                return (lhs.normalizedExercise, lhs.setNumber, lhs.weight, lhs.reps) < (rhs.normalizedExercise, rhs.setNumber, rhs.weight, rhs.reps)
            }
        }
    }

    private var shareText: String {
        WorkoutShareFormatter.summary(
            title: workout.title,
            date: workout.date,
            durationMinutes: workout.durationMinutes,
            calories: workout.calories,
            volumeKg: workout.volume,
            sets: orderedSets.map {
                WorkoutShareSet(
                    exercise: $0.exercise,
                    normalizedExercise: $0.normalizedExercise,
                    weight: $0.weight,
                    reps: $0.reps,
                    setNumber: $0.setNumber,
                    exerciseOrder: $0.exerciseOrder,
                    setType: $0.setType,
                    rpe: $0.rpe
                )
            },
            weightUnit: weightUnit,
            notes: workout.notes
        )
    }
    @State private var showingEditor = false
    @State private var showingDeleteConfirmation = false
    @State private var deleteError: String?
    @State private var isSyncingBiometrics = false
    @State private var syncStatusMessage: String?
    private let logger = Logger(subsystem: "com.personalstrengthcoach.app", category: "Persistence")
    private var groupedExercises: [(name: String, sets: [ExerciseSet])] {
        Dictionary(grouping: workout.sets, by: \.normalizedExercise)
            .map { (name: $0.key, sets: $0.value) }
            .sorted { lhs, rhs in
                let lhsOrder = lhs.sets.compactMap(\.exerciseOrder).min()
                let rhsOrder = rhs.sets.compactMap(\.exerciseOrder).min()
                switch (lhsOrder, rhsOrder) {
                case let (left?, right?) where left != right: return left < right
                case (_?, nil): return true
                case (nil, _?): return false
                default: return lhs.name < rhs.name
                }
            }
    }
    private var records: [String] {
        PerformanceEngine.personalRecords(in: workout, history: history)
    }

    private var trimmedNotes: String {
        workout.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func coachSummary(records: [String]) -> (title: String, detail: String) {
        WorkoutRecapEngine.coachSummary(
            records: records,
            volumeKg: workout.volume,
            setCount: workout.sets.count,
            weightUnit: weightUnit
        )
    }

    var body: some View {
        let sessionRecords = records
        let summary = coachSummary(records: sessionRecords)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                workoutMetrics

                if !sessionRecords.isEmpty {
                    SectionTitle("Personal records")
                    PersonalRecordsCard(records: sessionRecords)
                }

                SectionTitle("Session recap")
                CoachCard(title: summary.title, detail: summary.detail, icon: "sparkles")
                    .accessibilityElement(children: .combine)

                SectionTitle("Exercises")
                ForEach(groupedExercises, id: \.name) { exercise in
                    ExpandableExerciseCard(
                        name: exercise.name,
                        sets: exercise.sets,
                        hasPersonalRecord: sessionRecords.contains("\(exercise.name) estimated 1RM")
                    )
                }

                if !trimmedNotes.isEmpty {
                    SectionTitle("Notes")
                    CoachCard(title: "Your notes", detail: trimmedNotes, icon: "note.text")
                        .accessibilityElement(children: .combine)
                }

                healthSyncSection

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Text("Delete Workout")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.red)
                .accessibilityIdentifier("deleteWorkoutButton")
                .padding(.top, 4)
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(workout.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: shareText) {
                    Label("Share Workout", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("shareWorkoutButton")
                Button { showingEditor = true } label: { Label("Edit Workout", systemImage: "pencil") }
                    .accessibilityIdentifier("editWorkoutButton")
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

    private var workoutMetrics: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                volumeMetric
                durationMetric
                caloriesMetric
            }
            VStack(spacing: 10) {
                volumeMetric
                durationMetric
                caloriesMetric
            }
        }
    }

    private var volumeMetric: some View {
        WorkoutRecapMetric(title: "Volume", value: weightUnit.formattedWithUnit(workout.volume, fractionDigits: 0), icon: "dumbbell.fill", tint: .mint)
            .accessibilityIdentifier("workoutDetailMetric-Volume")
    }

    private var durationMetric: some View {
        WorkoutRecapMetric(title: "Duration", value: "\(workout.durationMinutes) min", icon: "clock.fill", tint: .indigo)
            .accessibilityIdentifier("workoutDetailMetric-Duration")
    }

    private var caloriesMetric: some View {
        // The logger does not collect calories yet; retain the third metric so
        // future calorie tracking can populate it without changing the layout.
        WorkoutRecapMetric(title: "Calories", value: workout.calories > 0 ? "\(workout.calories) kcal" : "—", icon: "flame.fill", tint: .orange, detail: workout.calories > 0 ? nil : "Not tracked")
            .accessibilityIdentifier("workoutDetailMetric-Calories")
    }

    private var healthSyncSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Apple Health")
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.title2)
                        .foregroundStyle(.mint)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wearable Biometrics")
                            .font(.subheadline.weight(.semibold))
                        Text(syncStatusMessage ?? "Attach heart rate, HRV, and active calories from Apple Health or wearable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("syncBiometricsStatusText")
                    }
                    Spacer()
                }

                Button {
                    syncBiometrics()
                } label: {
                    if isSyncingBiometrics {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(.primary)
                            Text("Syncing…")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Label("Sync Biometrics", systemImage: "arrow.trianglehead.2.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .tint(.mint)
                .disabled(isSyncingBiometrics)
                .accessibilityIdentifier("syncBiometricsWorkoutDetailButton")
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func syncBiometrics() {
        guard !isSyncingBiometrics else { return }
        isSyncingBiometrics = true
        Task {
            do {
                let result = try await WorkoutHealthKitService.syncRetroactiveBiometrics(for: workout, in: context)
                if result.heartRateSampleCount == 0 && result.hrvSampleCount == 0 && result.calories == nil {
                    syncStatusMessage = "No matching HealthKit samples found for this session’s time window."
                } else {
                    var parts: [String] = []
                    if result.heartRateSampleCount > 0 { parts.append("\(result.heartRateSampleCount) HR") }
                    if result.hrvSampleCount > 0 { parts.append("\(result.hrvSampleCount) HRV") }
                    if let cals = result.calories { parts.append("\(cals) kcal") }
                    syncStatusMessage = "Synced \(parts.joined(separator: ", "))"
                }
            } catch {
                syncStatusMessage = "Sync failed: \(error.localizedDescription)"
            }
            isSyncingBiometrics = false
        }
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

private struct WorkoutRecapMetric: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.headline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(detail.map { "\(value), \($0)" } ?? value)
    }
}

private struct PersonalRecordsCard: View {
    let records: [String]
    @State private var showsAllRecords = false

    private var displayedRecords: [String] {
        showsAllRecords ? records : Array(records.prefix(3))
    }

    private var remainingRecordCount: Int {
        max(0, records.count - displayedRecords.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(displayedRecords, id: \.self) { record in
                    Text(record)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.yellow.opacity(0.14), in: Capsule())
                }
                if remainingRecordCount > 0 {
                    Button("Show \(remainingRecordCount) more") {
                        showsAllRecords = true
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Capsule())
                }
            }
        }
        .padding(17)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct ExpandableExerciseCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("weightUnit") private var weightUnitRawValue = WeightUnit.defaultUnit.rawValue
    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRawValue) ?? .defaultUnit }
    let name: String
    let sets: [ExerciseSet]
    let hasPersonalRecord: Bool
    @State private var isExpanded = false

    private var orderedSets: [ExerciseSet] {
        sets.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.setNumber != rhs.element.setNumber {
                    return lhs.element.setNumber < rhs.element.setNumber
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private var volume: Double {
        sets.reduce(0) { total, set in
            guard set.setType != .warmup else { return total }
            return total + set.weight * Double(set.reps)
        }
    }

    private var bestSet: ExerciseSet? {
        WorkoutRecapEngine.bestSet(in: sets)
    }

    private var accessibilitySummary: String {
        var summary = "\(name)\(hasPersonalRecord ? ", personal record" : ""), \(sets.count) sets, \(weightUnit.formattedWithUnit(volume, fractionDigits: 0))"
        if let bestSet {
            summary += ". \(bestSetSummary(bestSet))"
        }
        return summary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text(name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .truncationMode(.tail)
                                .fixedSize(horizontal: false, vertical: true)
                            if hasPersonalRecord {
                                Image(systemName: "trophy.fill")
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                                    .accessibilityHidden(true)
                            }
                        }
                        Text("\(sets.count) sets · \(weightUnit.formattedWithUnit(volume, fractionDigits: 0))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let bestSet {
                            Text(bestSetSummary(bestSet))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("exerciseCard-\(name)")
            .accessibilityLabel(accessibilitySummary)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Hides the logged sets" : "Shows the logged sets")

            if isExpanded {
                Divider().padding(.vertical, 13)
                VStack(alignment: .leading, spacing: 11) {
                    ForEach(orderedSets, id: \.persistentModelID) { set in
                        ExerciseSetRecapRow(set: set)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .animation(reduceMotion ? nil : .snappy, value: isExpanded)
    }

    private func bestSetSummary(_ set: ExerciseSet) -> String {
        var summary = "Best set: \(set.weight > 0 ? weightUnit.formattedWithUnit(set.weight) : "Bodyweight") × \(set.reps)"
        if let rpe = set.rpe {
            summary += " · RPE \(String(format: "%.1f", rpe))"
        }
        return summary
    }
}

private struct ExerciseSetRecapRow: View {
    @AppStorage("weightUnit") private var weightUnitRawValue = WeightUnit.defaultUnit.rawValue
    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRawValue) ?? .defaultUnit }
    let set: ExerciseSet

    private var performanceSummary: String {
        "\(set.weight > 0 ? weightUnit.formattedWithUnit(set.weight) : "Bodyweight") × \(set.reps)"
    }

    private var metadataSummary: String? {
        let summary = [
            set.setType != .working ? set.setType.rawValue : nil,
            set.rpe.map { "RPE \(String(format: "%.1f", $0))" }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
        return summary.isEmpty ? nil : summary
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                setNumber
                Spacer(minLength: 10)
                performanceDetail(alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 4) {
                setNumber
                performanceDetail(alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var setNumber: some View {
        Text("Set \(set.setNumber)")
            .font(.subheadline.weight(.medium))
            .fixedSize(horizontal: true, vertical: true)
    }

    private func performanceDetail(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(performanceSummary)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: true, vertical: true)
            if let metadataSummary {
                Text(metadataSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: true)
            }
        }
    }
}
