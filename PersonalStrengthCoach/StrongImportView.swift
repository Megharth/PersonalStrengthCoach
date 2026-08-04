import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import OSLog

struct ImportedSet: Identifiable {
    let id = UUID()
    let exercise: String
    let weight: Double
    let reps: Int
}

struct ImportedWorkout: Identifiable {
    let id = UUID()
    let title: String
    let date: Date
    let sets: [ImportedSet]
}

struct StrongImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var showingFilePicker = false
    @State private var showingPaste = false
    @State private var imports: [ImportedWorkout] = []
    @State private var importError: String?
    private let logger = Logger(subsystem: "com.personalstrengthcoach.app", category: "Persistence")

    var body: some View {
        Group {
            if imports.isEmpty {
                ContentUnavailableView {
                    Label("Import from Strong", systemImage: "square.and.arrow.down")
                } description: {
                    Text("Choose a Strong CSV or JSON export, or paste the export contents.")
                } actions: {
                    Button("Choose file") { showingFilePicker = true }.buttonStyle(.borderedProminent)
                    Button("Paste export") { showingPaste = true }.padding(.top, 4)
                }
            } else {
                List {
                    Section("Ready to import") {
                        ForEach(imports) { workout in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(workout.title).font(.headline)
                                Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Text("\(workout.sets.count) sets · \(Int(workout.sets.reduce(0) { $0 + $1.weight * Double($1.reps) }).formatted()) kg")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Import from Strong")
        .toolbar {
            if !imports.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { Button("Import") { save() }.fontWeight(.semibold) }
            }
        }
        .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.commaSeparatedText, .json, .plainText]) { result in
            switch result {
            case .success(let url): load(url)
            case .failure(let error): importError = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingPaste) { PasteImportView { text in parse(text) } }
        .alert("Couldn’t import export", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: { Text(importError ?? "Unknown import error") }
    }

    private func load(_ url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do { parse(try String(contentsOf: url, encoding: .utf8)) }
        catch { importError = "The selected file could not be read as UTF-8 text." }
    }

    private func parse(_ text: String) {
        do {
            let parsed = try StrongImportParser.parse(text)
            guard !parsed.isEmpty else { throw StrongImportError.noWorkouts }
            imports = parsed
        } catch { importError = error.localizedDescription }
    }

    private func save() {
        do {
            for imported in imports {
                let workout = Workout(date: imported.date, title: imported.title, durationMinutes: 0)
                context.insert(workout)
                for (index, importedSet) in imported.sets.enumerated() {
                    let muscle = ExerciseCatalog.muscles(for: importedSet.exercise).first ?? .core
                    let set = ExerciseSet(exercise: importedSet.exercise, weight: importedSet.weight, reps: importedSet.reps, setNumber: index + 1, primaryMuscle: muscle)
                    set.workout = workout
                    context.insert(set)
                }
            }
            try context.save()
            dismiss()
        } catch {
            context.rollback()
            logger.error("Strong import save failed")
            importError = "The import could not be saved. Nothing was imported; try again."
        }
    }
}

private struct PasteImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    let submit: (String) -> Void
    var body: some View {
        NavigationStack {
            TextEditor(text: $text).font(.system(.body, design: .monospaced)).padding(8)
                .navigationTitle("Paste Strong Export")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Preview") { submit(text); dismiss() }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
        }
    }
}

enum StrongImportError: LocalizedError {
    case unsupported, noWorkouts
    var errorDescription: String? {
        switch self {
        case .unsupported: return "No workouts could be recognized. Use a CSV with Date, Exercise, Weight, and Reps columns, or a Strong JSON export."
        case .noWorkouts: return "This export did not contain any completed workout sets."
        }
    }
}

enum StrongImportParser {
    static func parse(_ text: String) throws -> [ImportedWorkout] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "{" || trimmed.first == "[" {
            let json = try JSONSerialization.jsonObject(with: Data(text.utf8))
            let workouts = parseJSON(json)
            guard !workouts.isEmpty else { throw StrongImportError.unsupported }
            return workouts
        }
        if let workout = parseShareText(trimmed) { return [workout] }
        let workouts = parseCSV(text)
        guard !workouts.isEmpty else { throw StrongImportError.unsupported }
        return workouts
    }

    private static func parseJSON(_ value: Any) -> [ImportedWorkout] {
        let candidates: [[String: Any]]
        if let array = value as? [[String: Any]] { candidates = array }
        else if let dictionary = value as? [String: Any] { candidates = dictionary.array(for: ["workouts", "data", "history"]) }
        else { candidates = [] }
        return candidates.compactMap { workout in
            let title = workout.string(for: ["name", "title", "workoutname"]) ?? "Imported Workout"
            let date = parseDate(workout.value(for: ["date", "startdate", "timestamp", "createdat"])) ?? .now
            let exercises = workout.array(for: ["exercises", "workoutexercises", "exerciseitems"])
            let sets = exercises.flatMap { exercise -> [ImportedSet] in
                let name = exercise.string(for: ["name", "exercisename", "title"]) ?? "Exercise"
                return exercise.array(for: ["sets", "exercisesets", "setdata"]).compactMap { item in
                    guard let reps = item.int(for: ["reps", "repetitions"]) else { return nil }
                    return ImportedSet(exercise: name, weight: item.double(for: ["weight", "weightkg", "load"]) ?? 0, reps: reps)
                }
            }
            return sets.isEmpty ? nil : ImportedWorkout(title: title, date: date, sets: sets)
        }
    }

    private static func parseCSV(_ text: String) -> [ImportedWorkout] {
        let rows = text.split(whereSeparator: \.isNewline).map { csvRow(String($0)) }
        guard let header = rows.first, header.count > 1 else { return [] }
        let keys = header.map { $0.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "") }
        func value(_ row: [String], _ names: [String]) -> String? { names.compactMap { keys.firstIndex(of: $0).flatMap { $0 < row.count ? row[$0] : nil } }.first }
        var grouped: [String: (title: String, date: Date, sets: [ImportedSet])] = [:]
        for row in rows.dropFirst() {
            guard let exercise = value(row, ["exercise", "exercisename", "name"]), let repsText = value(row, ["reps", "repetitions"]), let reps = Int(repsText.trimmingCharacters(in: .whitespaces)) else { continue }
            let title = value(row, ["workout", "workoutname", "title"]) ?? "Imported Workout"
            let date = parseDate(value(row, ["date", "timestamp", "startdate"])) ?? .now
            let weight = Double((value(row, ["weight", "weightkg", "load"]) ?? "0").replacingOccurrences(of: ",", with: ".")) ?? 0
            let key = "\(title)-\(Int(date.timeIntervalSince1970))"
            grouped[key, default: (title, date, [])].sets.append(ImportedSet(exercise: exercise, weight: weight, reps: reps))
        }
        return grouped.values.map { ImportedWorkout(title: $0.title, date: $0.date, sets: $0.sets) }.sorted { $0.date > $1.date }
    }

    /// Parses Strong's shared-workout text: an activity title, natural-language date,
    /// exercise headings, and lines such as “Set 1: 75 lb × 8”.
    private static func parseShareText(_ text: String) -> ImportedWorkout? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("http") }
        guard lines.count >= 3, lines.contains(where: { $0.lowercased().hasPrefix("set ") }) else { return nil }
        let title = lines[0]
        let date = parseShareDate(lines[1]) ?? .now
        let expression = try? NSRegularExpression(pattern: "^Set\\s+\\d+\\s*:\\s*([0-9]+(?:\\.[0-9]+)?)\\s*(lb|lbs|kg)?\\s*[×x]\\s*(\\d+)", options: [.caseInsensitive])
        var exercise = "Exercise"
        var sets: [ImportedSet] = []
        for line in lines.dropFirst(2) {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = expression?.firstMatch(in: line, range: range) else { exercise = line; continue }
            guard let weightRange = Range(match.range(at: 1), in: line), let repsRange = Range(match.range(at: 3), in: line), let weight = Double(line[weightRange]), let reps = Int(line[repsRange]) else { continue }
            let unit = match.range(at: 2).location == NSNotFound ? "kg" : String(line[Range(match.range(at: 2), in: line)!]).lowercased()
            let weightKg = unit.hasPrefix("lb") ? weight * 0.453_592_37 : weight
            sets.append(ImportedSet(exercise: exercise, weight: weightKg, reps: reps))
        }
        return sets.isEmpty ? nil : ImportedWorkout(title: title, date: date, sets: sets)
    }

    private static func parseShareDate(_ string: String) -> Date? {
        let normalized = string.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
        return formatter.date(from: normalized)
    }

    private static func csvRow(_ line: String) -> [String] {
        var result: [String] = []; var cell = ""; var quoted = false
        for character in line {
            if character == "\"" { quoted.toggle() }
            else if character == "," && !quoted { result.append(cell.trimmingCharacters(in: .whitespaces)); cell = "" }
            else { cell.append(character) }
        }
        result.append(cell.trimmingCharacters(in: .whitespaces)); return result
    }

    private static func parseDate(_ value: Any?) -> Date? {
        if let date = value as? Date { return date }
        if let seconds = value as? TimeInterval { return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1_000 : seconds) }
        guard let string = value as? String else { return nil }
        if let date = ISO8601DateFormatter().date(from: string) { return date }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "M/d/yyyy HH:mm", "M/d/yyyy"] { formatter.dateFormat = format; if let date = formatter.date(from: string) { return date } }
        return nil
    }
}

private extension Dictionary where Key == String, Value == Any {
    func value(for names: [String]) -> Any? {
        let normalized = Dictionary(uniqueKeysWithValues: map { ($0.key.lowercased().replacingOccurrences(of: "_", with: ""), $0.value) })
        return names.lazy.compactMap { normalized[$0] }.first
    }
    func string(for names: [String]) -> String? { value(for: names).map { "\($0)" }.flatMap { $0.isEmpty ? nil : $0 } }
    func double(for names: [String]) -> Double? { if let value = value(for: names) as? NSNumber { return value.doubleValue }; return string(for: names).flatMap(Double.init) }
    func int(for names: [String]) -> Int? { if let value = value(for: names) as? NSNumber { return value.intValue }; return string(for: names).flatMap(Int.init) }
    func array(for names: [String]) -> [[String: Any]] { value(for: names) as? [[String: Any]] ?? [] }
}
