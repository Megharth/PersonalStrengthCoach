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
    // Parsed from the Strong "Duration"/"Workout Duration" CSV column when
    // present; JSON and share-text imports have no duration source and keep
    // the default of 0.
    var durationMinutes: Int = 0
}

struct StrongImportResult {
    let workouts: [ImportedWorkout]
    let skippedRows: Int
    let failedRows: Int
}

struct StrongImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var existingWorkouts: [Workout]
    @State private var showingFilePicker = false
    @State private var showingPaste = false
    @State private var imports: [ImportedWorkout] = []
    @State private var importError: String?
    @State private var importSummary: String?
    @State private var skippedRows = 0
    @State private var failedRows = 0
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
        .alert("Import complete", isPresented: Binding(get: { importSummary != nil }, set: { if !$0 { importSummary = nil } })) {
            Button("Done") { dismiss() }
        } message: { Text(importSummary ?? "") }
    }

    private func load(_ url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do { parse(try String(contentsOf: url, encoding: .utf8)) }
        catch { importError = "The selected file could not be read as UTF-8 text." }
    }

    private func parse(_ text: String) {
        do {
            let result = try StrongImportParser.parse(text)
            imports = result.workouts
            skippedRows = result.skippedRows
            failedRows = result.failedRows
        } catch { importError = error.localizedDescription }
    }

    private func save() {
        var importedCount = 0
        var duplicateCount = 0
        var knownWorkouts = existingWorkouts
        do {
            for imported in imports {
                if knownWorkouts.contains(where: { Self.isDuplicate($0, imported) }) {
                    duplicateCount += 1
                    continue
                }
                let workout = Workout(date: imported.date, title: imported.title, durationMinutes: imported.durationMinutes)
                context.insert(workout)
                for (index, importedSet) in imported.sets.enumerated() {
                    let muscle = ExerciseCatalog.muscles(for: importedSet.exercise).first ?? .core
                    let set = ExerciseSet(exercise: importedSet.exercise, weight: importedSet.weight, reps: importedSet.reps, setNumber: index + 1, primaryMuscle: muscle)
                    set.workout = workout
                    context.insert(set)
                }
                knownWorkouts.append(workout)
                importedCount += 1
            }
            try context.save()
            importSummary = "Imported \(importedCount) workout(s). Skipped \(skippedRows) row(s), failed \(failedRows) row(s), and ignored \(duplicateCount) duplicate workout(s)."
        } catch {
            context.rollback()
            logger.error("Strong import save failed")
            importError = "The import could not be saved. Nothing was imported; try again."
        }
    }

    static func isDuplicate(_ stored: Workout, _ imported: ImportedWorkout) -> Bool {
        stored.title.caseInsensitiveCompare(imported.title) == .orderedSame &&
        abs(stored.date.timeIntervalSince(imported.date)) < 60 &&
        stored.sets.count == imported.sets.count &&
        zip(stored.sets.sorted { $0.setNumber < $1.setNumber }, imported.sets).allSatisfy { storedSet, importedSet in
            storedSet.exercise.caseInsensitiveCompare(importedSet.exercise) == .orderedSame &&
            abs(storedSet.weight - importedSet.weight) < 0.01 &&
            storedSet.reps == importedSet.reps
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
    case unsupported, noWorkouts, fileTooLarge, malformedExport
    var errorDescription: String? {
        switch self {
        case .unsupported: return "No workouts could be recognized. Use a CSV with Date, Exercise, Weight, and Reps columns, or a Strong JSON export."
        case .noWorkouts: return "This export did not contain any completed workout sets."
        case .fileTooLarge: return "This export is too large to import. Choose a file smaller than 10 MB."
        case .malformedExport: return "The export is malformed. Check that it is a valid Strong CSV or JSON export and try again."
        }
    }
}

enum StrongImportParser {
    static func parse(_ text: String) throws -> StrongImportResult {
        guard text.utf8.count <= 10_000_000 else { throw StrongImportError.fileTooLarge }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "{" || trimmed.first == "[" {
            let json: Any
            do {
                json = try JSONSerialization.jsonObject(with: Data(text.utf8))
            } catch {
                throw StrongImportError.malformedExport
            }
            let result = parseJSON(json)
            guard !result.workouts.isEmpty else { throw StrongImportError.unsupported }
            return result
        }
        if let result = parseShareText(trimmed) { return result }
        let result = parseCSV(text)
        guard !result.workouts.isEmpty else { throw StrongImportError.unsupported }
        return result
    }

    private static func parseJSON(_ value: Any) -> StrongImportResult {
        let candidates: [[String: Any]]
        if let array = value as? [[String: Any]] { candidates = array }
        else if let dictionary = value as? [String: Any] { candidates = dictionary.array(for: ["workouts", "data", "history"]) }
        else { candidates = [] }
        var skippedRows = 0
        var failedRows = 0
        let workouts = candidates.compactMap { workout -> ImportedWorkout? in
            let title = workout.string(for: ["name", "title", "workoutname"]) ?? "Imported Workout"
            guard let date = parseDate(workout.value(for: ["date", "startdate", "timestamp", "createdat"])) else {
                failedRows += 1
                return nil
            }
            let exercises = workout.array(for: ["exercises", "workoutexercises", "exerciseitems"])
            let sets = exercises.flatMap { exercise -> [ImportedSet] in
                let name = exercise.string(for: ["name", "exercisename", "title"]) ?? "Exercise"
                return exercise.array(for: ["sets", "exercisesets", "setdata"]).compactMap { item in
                    guard let reps = item.int(for: ["reps", "repetitions"]) else { failedRows += 1; return nil }
                    guard let weight = item.weightKg() else { failedRows += 1; return nil }
                    guard let set = makeSet(exercise: name, weight: weight, reps: reps) else { failedRows += 1; return nil }
                    return set
                }
            }
            guard !sets.isEmpty else { skippedRows += 1; return nil }
            return ImportedWorkout(title: title, date: date, sets: sets)
        }
        return StrongImportResult(workouts: workouts, skippedRows: skippedRows, failedRows: failedRows)
    }

    private static func parseCSV(_ text: String) -> StrongImportResult {
        let rows = text.split(whereSeparator: \.isNewline).map { csvRow(String($0)) }
        guard let header = rows.first, header.count > 1 else { return StrongImportResult(workouts: [], skippedRows: 0, failedRows: 0) }
        let keys = header.map { $0.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "") }
        func value(_ row: [String], _ names: [String]) -> String? { names.compactMap { keys.firstIndex(of: $0).flatMap { $0 < row.count ? row[$0] : nil } }.first }
        var grouped: [String: (title: String, date: Date, durationMinutes: Int, sets: [ImportedSet])] = [:]
        var skippedRows = 0
        var failedRows = 0
        for row in rows.dropFirst() {
            if row.allSatisfy({ $0.isEmpty }) { skippedRows += 1; continue }
            guard let exercise = value(row, ["exercise", "exercisename", "name"]), let repsText = value(row, ["reps", "repetitions"]), let reps = Int(repsText.trimmingCharacters(in: .whitespaces)) else { failedRows += 1; continue }
            let title = value(row, ["workout", "workoutname", "title"]) ?? "Imported Workout"
            guard let date = parseDate(value(row, ["date", "timestamp", "startdate"])) else { failedRows += 1; continue }
            guard let weightColumn = keys.firstIndex(where: { ["weight", "weightkg", "weightlb", "weightlbs", "load"].contains($0) }), weightColumn < row.count else { failedRows += 1; continue }
            guard let weight = weightKg(row[weightColumn], header: keys[weightColumn]) else { failedRows += 1; continue }
            guard let importedSet = makeSet(exercise: exercise, weight: weight, reps: reps) else { failedRows += 1; continue }
            let durationMinutes = parseDurationMinutes(value(row, ["duration", "workoutduration"]))
            let key = "\(title)-\(Int(date.timeIntervalSince1970))"
            grouped[key, default: (title, date, durationMinutes, [])].sets.append(importedSet)
        }
        return StrongImportResult(workouts: grouped.values.map { ImportedWorkout(title: $0.title, date: $0.date, sets: $0.sets, durationMinutes: $0.durationMinutes) }.sorted { $0.date > $1.date }, skippedRows: skippedRows, failedRows: failedRows)
    }

    /// Parses a Strong "Duration"/"Workout Duration" CSV value into whole minutes.
    /// Accepts a bare integer (minutes), "1h 5m"-style strings, or falls back to 0
    /// for anything missing or unparseable. Never fails the row. Result is clamped
    /// to 0...240 so a garbled or negative cell can't produce a nonsensical duration.
    private static func parseDurationMinutes(_ value: String?) -> Int {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return 0 }
        if let minutes = Int(trimmed) { return max(0, min(240, minutes)) }
        let expression = try? NSRegularExpression(pattern: "^(?:(\\d+)h)?\\s*(?:(\\d+)m)?$", options: [.caseInsensitive])
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = expression?.firstMatch(in: trimmed, range: range) else { return 0 }
        let hoursRange = Range(match.range(at: 1), in: trimmed)
        let minutesRange = Range(match.range(at: 2), in: trimmed)
        guard hoursRange != nil || minutesRange != nil else { return 0 }
        let hours = hoursRange.flatMap { Int(trimmed[$0]) } ?? 0
        let minutes = minutesRange.flatMap { Int(trimmed[$0]) } ?? 0
        return max(0, min(240, hours * 60 + minutes))
    }

    /// Parses Strong's shared-workout text: an activity title, natural-language date,
    /// exercise headings, and lines such as “Set 1: 75 lb × 8”.
    private static func parseShareText(_ text: String) -> StrongImportResult? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("http") }
        guard lines.count >= 3, lines.contains(where: { $0.lowercased().hasPrefix("set ") }) else { return nil }
        let title = lines[0]
        guard let date = parseShareDate(lines[1]) else { return nil }
        let expression = try? NSRegularExpression(pattern: "^Set\\s+\\d+\\s*:\\s*([0-9]+(?:\\.[0-9]+)?)\\s*(lb|lbs|kg)?\\s*[×x]\\s*(\\d+)", options: [.caseInsensitive])
        var exercise = "Exercise"
        var sets: [ImportedSet] = []
        var failedRows = 0
        for line in lines.dropFirst(2) {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = expression?.firstMatch(in: line, range: range) else {
                if line.lowercased().hasPrefix("set ") { failedRows += 1 } else { exercise = line }
                continue
            }
            guard let weightRange = Range(match.range(at: 1), in: line), let repsRange = Range(match.range(at: 3), in: line), let weight = Double(line[weightRange]), let reps = Int(line[repsRange]) else {
                failedRows += 1
                continue
            }
            let unit = match.range(at: 2).location == NSNotFound ? "kg" : String(line[Range(match.range(at: 2), in: line)!]).lowercased()
            let weightKg = unit.hasPrefix("lb") ? weight * 0.453_592_37 : weight
            if let set = makeSet(exercise: exercise, weight: weightKg, reps: reps) { sets.append(set) } else { failedRows += 1 }
        }
        return sets.isEmpty ? nil : StrongImportResult(workouts: [ImportedWorkout(title: title, date: date, sets: sets)], skippedRows: 0, failedRows: failedRows)
    }

    private static func makeSet(exercise: String, weight: Double, reps: Int) -> ImportedSet? {
        let name = exercise.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, weight.isFinite, weight >= 0, reps > 0 else { return nil }
        return ImportedSet(exercise: name, weight: weight, reps: reps)
    }

    private static func weightKg(_ value: String, header: String) -> Double? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        let parts = normalized.split(separator: " ", maxSplits: 1).map(String.init)
        guard let rawWeight = parts.first, let weight = Double(rawWeight), weight.isFinite else { return nil }
        let unit = parts.count == 2 ? parts[1].lowercased() : (header.contains("lb") ? "lb" : "kg")
        guard unit == "kg" || unit == "kgs" || unit == "kilogram" || unit == "kilograms" || unit == "lb" || unit == "lbs" || unit == "pound" || unit == "pounds" else { return nil }
        let kilograms = unit.hasPrefix("lb") || unit.hasPrefix("pound") ? weight * 0.453_592_37 : weight
        return kilograms >= 0 ? kilograms : nil
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

    func weightKg() -> Double? {
        let raw = value(for: ["weightlb", "weightlbs", "weightkg", "weight", "load"])
        let number: Double
        if let value = raw as? NSNumber { number = value.doubleValue }
        else if let string = raw as? String {
            let parts = string.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
                .split(separator: " ", maxSplits: 1)
            guard let parsed = parts.first.flatMap({ Double($0) }) else { return nil }
            number = parsed
            let unit = parts.count == 2 ? String(parts[1]).lowercased() : (value(for: ["unit", "weightunit"]).map { "\($0)".lowercased() } ?? "")
            return convertToKg(number, unit: unit)
        } else { return nil }
        let key = firstKey(for: ["weightlb", "weightlbs", "weightkg", "weight", "load"])
        let unit = value(for: ["unit", "weightunit"]).map { "\($0)".lowercased() } ?? ""
        return convertToKg(number, unit: unit.isEmpty ? (key?.contains("lb") == true ? "lb" : "kg") : unit)
    }

    private func firstKey(for names: [String]) -> String? {
        let normalized = Dictionary(uniqueKeysWithValues: map { ($0.key.lowercased().replacingOccurrences(of: "_", with: ""), $0.value) })
        return names.first(where: { normalized[$0] != nil })
    }

    private func convertToKg(_ weight: Double, unit: String) -> Double? {
        guard weight.isFinite else { return nil }
        let normalized = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized == "kg" || normalized == "kgs" || normalized == "kilogram" || normalized == "kilograms" || normalized == "lb" || normalized == "lbs" || normalized == "pound" || normalized == "pounds" else { return nil }
        let kilograms = normalized.hasPrefix("lb") || normalized.hasPrefix("pound") ? weight * 0.453_592_37 : weight
        return kilograms >= 0 ? kilograms : nil
    }
}
