import SwiftUI
import Charts

struct RecoveryView: View {
    let workouts: [Workout]; let recoveryDays: [DailyRecovery]
    var body: some View { NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 18) {
        Text("Recovery").font(.largeTitle.bold())
        let score = RecoveryEngine.readiness(today: recoveryDays.first, recent: recoveryDays, workouts: workouts)
        let recent = Array(recoveryDays.prefix(7))
        let count = Double(recent.count)
        let averageSleep = count == 0 ? 0 : recent.map(\.sleepHours).reduce(0, +) / count
        let averageHRV = count == 0 ? 0 : recent.map(\.hrv).reduce(0, +) / count
        ReadinessCard(result: score)
        Text("Muscle recovery").font(.title3.bold())
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) { ForEach(MuscleGroup.allCases) { muscle in let value = RecoveryEngine.muscleRecovery(muscle, workouts: workouts); MuscleRecoveryTile(muscle: muscle, value: value) } }
        Text("Weekly averages").font(.title3.bold()).padding(.top, 4)
        HStack { MetricCard(title: "Sleep", value: String(format: "%.1f", averageSleep), unit: "hours", icon: "bed.double.fill", tint: .indigo); MetricCard(title: "HRV", value: "\(Int(averageHRV))", unit: "ms", icon: "waveform.path.ecg", tint: .pink) }
    }.padding() }.background(Color(uiColor: .systemGroupedBackground)) } }
}

struct MuscleRecoveryTile: View {
    let muscle: MuscleGroup; let value: Int
    var tint: Color { value >= 70 ? .mint : value >= 45 ? .yellow : .red }
    var body: some View { VStack(alignment: .leading, spacing: 8) { HStack { Text(muscle.rawValue).font(.subheadline.weight(.semibold)); Spacer(); Text("\(value)%").font(.caption.weight(.bold)).foregroundStyle(tint) }; ProgressView(value: Double(value), total: 100).tint(tint); Text(value >= 70 ? "Recovered" : value >= 45 ? "Recovering" : "Fatigued").font(.caption).foregroundStyle(.secondary) }.padding(13).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16)) }
}

struct ExerciseDetailView: View {
    let exercise: String; let sets: [ExerciseSet]
    var relevant: [ExerciseSet] { sets.filter { $0.normalizedExercise == exercise } }
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 18) { Text(exercise).font(.largeTitle.bold()); HStack { MetricCard(title: "Est. 1RM", value: "\(Int(PerformanceEngine.estimated1RM(for: exercise, sets: sets)))", unit: "kg", icon: "bolt.fill", tint: .orange); MetricCard(title: "Best set", value: relevant.map { Int($0.weight) }.max().map(String.init) ?? "—", unit: "kg", icon: "trophy.fill", tint: .yellow) }; TrendChart(title: "Estimated 1RM", points: relevant.sorted { ($0.workout?.date ?? .distantPast) < ($1.workout?.date ?? .distantPast) }.map(\.estimated1RM), tint: .mint); CoachCard(title: "Progression", detail: "Your top-end strength is trending upward. Prioritize small, repeatable progressions over rapid load jumps.", icon: "sparkles") }.padding() }.background(Color(uiColor: .systemGroupedBackground)).navigationBarTitleDisplayMode(.inline) }
}

struct CoachView: View {
    let workouts: [Workout]; let recoveryDays: [DailyRecovery]
    @State private var question = ""; @State private var messages = [("Coach", "Ask about your training, recovery, or next session.")]; @State private var isLoading = false
    var body: some View { NavigationStack { VStack(spacing: 0) { ScrollView { LazyVStack(alignment: .leading, spacing: 14) { ForEach(messages.indices, id: \.self) { i in let message = messages[i]; VStack(alignment: message.0 == "You" ? .trailing : .leading, spacing: 4) { Text(message.0).font(.caption.weight(.bold)).foregroundStyle(.secondary); Text(message.1).padding(13).background(message.0 == "You" ? Color.mint.opacity(0.25) : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16)) }.frame(maxWidth: .infinity, alignment: message.0 == "You" ? .trailing : .leading) } }.padding() }.background(Color(uiColor: .systemGroupedBackground))
        HStack { TextField("Ask your coach", text: $question, axis: .vertical).textFieldStyle(.roundedBorder); Button { send() } label: { if isLoading { ProgressView() } else { Image(systemName: "arrow.up.circle.fill").font(.title2) } }.disabled(isLoading || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }.padding()
    }.navigationTitle("Coach") } }
    private func send() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        messages.append(("You", text)); question = ""; isLoading = true
        let readiness = RecoveryEngine.readiness(today: recoveryDays.first, recent: recoveryDays, workouts: workouts)
        let recommendation = RecommendationEngine.nextWorkout(workouts: workouts)
        let context = AIInsightContext(readinessScore: readiness.score, sleepHours: recoveryDays.first?.sleepHours ?? 0, hrv: recoveryDays.first?.hrv ?? 0, restingHeartRate: recoveryDays.first?.restingHeartRate ?? 0, weeklyVolume: PerformanceEngine.weeklyVolume(workouts), recommendation: recommendation.detail)
        Task {
            let reply: String
            do { reply = try await AIInsightService.requestInsight(question: text, context: context) }
            catch { reply = "Coach AI is unavailable right now. Your local recommendation: \(recommendation.detail)" }
            messages.append(("Coach", reply)); isLoading = false
        }
    }
}
