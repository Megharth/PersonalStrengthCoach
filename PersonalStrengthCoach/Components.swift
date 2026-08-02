import SwiftUI
import Charts

struct ReadinessCard: View {
    let result: ReadinessResult
    private var tint: Color { result.color == "Green" ? .mint : result.color == "Yellow" ? .yellow : .red }
    var body: some View { HStack(spacing: 18) {
        ZStack { Circle().stroke(tint.opacity(0.2), lineWidth: 11); Circle().trim(from: 0, to: Double(result.score) / 100).stroke(tint, style: StrokeStyle(lineWidth: 11, lineCap: .round)).rotationEffect(.degrees(-90)); VStack(spacing: 0) { Text("\(result.score)").font(.title.bold()); Text("/ 100").font(.caption).foregroundStyle(.secondary) } }.frame(width: 105, height: 105)
        VStack(alignment: .leading, spacing: 8) { Text("READINESS").font(.caption.weight(.bold)).foregroundStyle(tint); Text(result.color == "Green" ? "Ready to perform" : "Train with intent").font(.title3.bold()); Text(result.factors.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
        Spacer()
    }.padding(18).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24)) }
}

struct MetricCard: View {
    let title: String; let value: String; let unit: String; let icon: String; let tint: Color
    var body: some View { VStack(alignment: .leading, spacing: 12) { Image(systemName: icon).foregroundStyle(tint); Spacer(); Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.title2.bold()) + Text(" \(unit)").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, minHeight: 120, alignment: .leading).padding(14).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18)) }
}

struct CoachCard: View {
    let title: String; let detail: String; let icon: String
    var body: some View { HStack(alignment: .top, spacing: 14) { Image(systemName: icon).font(.title3).foregroundStyle(.mint).frame(width: 28); VStack(alignment: .leading, spacing: 6) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }; Spacer() }.padding(17).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18)) }
}

struct SectionTitle: View { let _title: String; init(_ title: String) { _title = title }; var body: some View { Text(_title).font(.title3.bold()).padding(.top, 4) } }

struct TrendChart: View {
    let title: String; let points: [Double]; let tint: Color
    var body: some View { VStack(alignment: .leading) { Text(title).font(.headline); Chart(Array(points.enumerated()), id: \.offset) { point in LineMark(x: .value("Day", point.offset), y: .value("Value", point.element)).interpolationMethod(.catmullRom).foregroundStyle(tint).lineStyle(StrokeStyle(lineWidth: 3)); AreaMark(x: .value("Day", point.offset), y: .value("Value", point.element)).foregroundStyle(tint.opacity(0.12)) }.chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 130) }.padding(16).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18)) }
}
