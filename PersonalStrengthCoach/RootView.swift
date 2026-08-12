import SwiftUI
import SwiftData
import OSLog

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]
    @Query(sort: \DailyRecovery.date, order: .reverse) private var recoveryDays: [DailyRecovery]
    @State private var selectedTab = 0
    @State private var healthKitError: String?
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
        .alert("Couldn’t sync Health data", isPresented: Binding(get: { healthKitError != nil }, set: { if !$0 { healthKitError = nil } })) {
            Button("Retry") { Task { await syncHealthKit() } }
            Button("Not now", role: .cancel) { }
        } message: { Text(healthKitError ?? "Health data could not be refreshed.") }
    }

    private func syncHealthKit() async {
        do {
            try await HealthKitService.sync(context: context)
        } catch {
            logger.error("HealthKit sync failed")
            healthKitError = "Check Health permissions and try again."
        }
    }
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
    var body: some View {
        let strengthTrend = PerformanceEngine.strengthTrend(in: workouts)
        NavigationStack { ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Dashboard").font(.largeTitle.bold())
                HStack { MetricCard(title: "Weekly Volume", value: "\(Int(PerformanceEngine.weeklyVolume(workouts) / 1_000))k", unit: "kg", icon: "dumbbell.fill", tint: .orange); MetricCard(title: "Workouts", value: "\(workouts.filter { $0.date > .now.addingTimeInterval(-604800) }.count)", unit: "this week", icon: "calendar", tint: .mint) }
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
    let workouts: [Workout]
    @State private var showingLogger = false
    var body: some View { NavigationStack { List {
        ForEach(workouts) { workout in NavigationLink { WorkoutDetailView(workout: workout, history: workouts) } label: {
            HStack { Image(systemName: "dumbbell.fill").foregroundStyle(.mint).frame(width: 30); VStack(alignment: .leading) { Text(workout.title).font(.headline); Text(workout.date.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary) }; Spacer(); VStack(alignment: .trailing) { Text("\(Int(workout.volume).formatted()) kg").font(.subheadline.weight(.semibold)); Text("\(workout.durationMinutes) min").font(.caption).foregroundStyle(.secondary) } }
        } }
        }
        .navigationTitle("Workout History")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showingLogger = true } label: { Label("Log workout", systemImage: "plus.circle") }
                    NavigationLink { RoutinesListView() } label: { Label("Routines", systemImage: "list.bullet.rectangle") }
                    NavigationLink { StrongImportView() } label: { Label("Import from Strong", systemImage: "square.and.arrow.down") }
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingLogger) { WorkoutLoggerView() }
    } }
}

struct WorkoutDetailView: View {
    let workout: Workout; let history: [Workout]
    private var groupedExercises: [(name: String, sets: [ExerciseSet])] {
        Dictionary(grouping: workout.sets, by: \.normalizedExercise)
            .map { (name: $0.key, sets: $0.value) }
            .sorted { $0.name < $1.name }
    }
    var body: some View { List {
        Section("Session") { LabeledContent("Volume", value: "\(Int(workout.volume).formatted()) kg"); LabeledContent("Duration", value: "\(workout.durationMinutes) min"); LabeledContent("Calories", value: "\(workout.calories) kcal") }
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
                Text("High-volume session completed (\(Int(workout.volume).formatted()) kg). Focus on adequate protein intake and sleep tonight.")
            } else {
                Text("Solid training session (\(workout.sets.count) sets). Keep your compounds controlled and preserve clean technique.")
            }
        }
    }.navigationTitle(workout.title).navigationBarTitleDisplayMode(.inline) }
}

private struct ExerciseRow: View {
    let name: String
    let sets: [ExerciseSet]
    let allSets: [ExerciseSet]
    private var volume: Double { sets.reduce(0) { total, set in total + set.weight * Double(set.reps) } }
    var body: some View {
        NavigationLink {
            ExerciseDetailView(exercise: name, sets: allSets)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                Text("\(sets.count) sets · \(Int(volume).formatted()) kg")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
