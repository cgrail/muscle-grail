import CryptoKit
import Foundation
import SwiftData

/// GymBook's log export: an XML file with a `<log>` per set, the newest workout first. Importing it brings the history over
/// from GymBook, with a plan per workout; exporting writes the history back in its format.
// shortcut: reads and writes the German export's dates (dd.MM.yy HH:mm); add an English GymBook's once there is a sample
public enum GymBook {
    /// One `<log>`: a set, or a cardio entry, which has no reps.
    public struct Log: Equatable, Sendable {
        public var date: Date
        public var workout: String
        public var exercise: String
        public var reps: Int?
        public var weightKg = 0.0
        /// The unit GymBook showed the weight in, the machine's.
        public var unit = WeightUnit.kg
        /// A planned set that wasn't done.
        public var skipped = false
    }

    /// The logs in `data`. A file that isn't GymBook's log export throws.
    public static func logs(_ data: Data) throws -> [Log] {
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse(), reader.isLogs else { throw parser.parserError ?? CocoaError(.fileReadCorruptFile) }
        return reader.logs
    }

    /// The exercises with sets, to map to exercises here before importing. Cardio has no reps and stays out.
    public static func exercises(in logs: [Log]) -> [String] {
        Set(logs.filter { $0.reps != nil }.map(\.exercise)).sorted()
    }

    static func dateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd.MM.yy HH:mm"
        return formatter
    }

    /// The same id for the same row on every import, so importing a file again adds nothing.
    static func id(_ key: String) -> UUID {
        SHA256.hash(data: Data(key.utf8)).withUnsafeBytes { UUID(uuid: $0.load(as: uuid_t.self)) }
    }

    /// The workout a log belongs to: GymBook's workout of that day.
    static func session(_ log: Log) -> String {
        let day = Calendar.current.dateComponents([.year, .month, .day], from: log.date)
        return "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0) \(log.workout)"
    }
}

private final class Reader: NSObject, XMLParserDelegate {
    let format = GymBook.dateFormatter()
    var logs: [GymBook.Log] = []
    var isLogs = false
    private var fields: [String: String] = [:]
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if name == "logs" { isLogs = true }
        if name == "log" { fields = [:] }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "log" {
            if let log = log() { logs.append(log) }
        } else if fields[name] == nil { // a cardio entry's second <time> is its duration
            fields[name] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func log() -> GymBook.Log? {
        guard let day = fields["date"], let date = format.date(from: "\(day) \(fields["time"] ?? "00:00")"),
              let workout = fields["workout"], let exercise = fields["exercise"] else { return nil }
        let weight = (fields["weight"] ?? "").split(whereSeparator: \.isWhitespace) // "38,00 kg", with a narrow no-break space
        let unit = weight.last.flatMap { WeightUnit(rawValue: String($0)) } ?? .kg
        return GymBook.Log(
            date: date, workout: workout, exercise: exercise, reps: fields["reps"].flatMap { Int($0) },
            weightKg: unit.kg(weight.first.flatMap { Weights.parse(String($0)) } ?? 0), unit: unit,
            skipped: ["Ja", "Yes"].contains(fields["skipped"] ?? "")
        )
    }
}

public extension ModelContext {
    /// Imports GymBook's `logs`: each workout with the sets done in it, under the plan of its name. A workout name without a
    /// plan gets one with its newest workout's exercises, sets, reps and weight. `exercises` maps a GymBook name to an
    /// exercise here; one it leaves out becomes the exercise by that name, else a new one of the user's own. An exercise
    /// GymBook last showed in lb shows in lb. Returns how many workouts it added: importing the same logs again adds none.
    @discardableResult
    func importGymBook(_ logs: [GymBook.Log], exercises: [String: String] = [:]) -> Int {
        let logs = logs.filter { $0.reps != nil }
        var ids = exercises
        for name in GymBook.exercises(in: logs) where ids[name] == nil {
            ids[name] = catalogID(named: name) ?? createExercise(named: name)
        }
        for name in GymBook.exercises(in: logs) where weightUnit(of: ids[name]!) != .lb {
            if logs.filter({ $0.exercise == name }).max(by: { $0.date < $1.date })?.unit == .lb { setUnit(ids[name]!, to: .lb) }
        }
        // Newest first, so the plans GymBook trained last come first.
        let sessions = Dictionary(grouping: logs, by: GymBook.session).sorted { $0.value[0].date > $1.value[0].date }
        var plans = Dictionary(((try? fetch(FetchDescriptor<Plan>())) ?? []).map { ($0.name, $0.id) }) { first, _ in first }
        for (_, rows) in sessions where plans[rows[0].workout] == nil {
            let plan = addPlan()
            rename(plan, to: rows[0].workout)
            for name in rows.map(\.exercise).reduce(into: [String](), { if !$0.contains($1) { $0.append($1) } }) {
                let sets = rows.filter { $0.exercise == name } // skipped ones too: they were planned
                setTargets(add(ids[name]!, to: plan), sets: sets.count, reps: sets.last!.reps!, weightKg: sets.last!.weightKg)
            }
            plans[rows[0].workout] = plan.id
        }
        var added = 0
        for (session, rows) in sessions {
            let id = GymBook.id("workout \(session)")
            let done = rows.filter { !$0.skipped }.sorted { $0.date < $1.date }
            guard workout(id) == nil, let start = done.first?.date else { continue }
            record(.startWorkout(id: id, plan: plans[rows[0].workout]!, start: start))
            for (index, log) in done.enumerated() { // a second apart, so the sets of one minute keep their order
                record(.logSet(id: GymBook.id("set \(index) \(session)"), workout: id, exerciseID: ids[log.exercise]!,
                               reps: log.reps!, weightKg: log.weightKg, date: log.date.addingTimeInterval(Double(index))))
            }
            record(.finishWorkout(id: id, end: done.last!.date.addingTimeInterval(Double(done.count))))
            try? save() // a workout at a time: each change's lookup by id slows with every unsaved one
            added += 1
        }
        return added
    }

    /// Every workout as GymBook's log export, the newest first, each weight in its exercise's unit.
    func gymBookExport() throws -> Data {
        let format = GymBook.dateFormatter()
        let number = FloatingPointFormatStyle<Double>.number.locale(Locale(identifier: "de")).precision(.fractionLength(2)).grouping(.never)
        var xml = "<logs>"
        for workout in try fetch(Workout.history) {
            for set in (workout.sets ?? []).sorted(by: { $0.date < $1.date }) {
                let unit = weightUnit(of: set.exerciseID)
                let date = format.string(from: set.date).split(separator: " ")
                let weight = set.weightKg > 0 ? "<weight>\(unit.value(set.weightKg).formatted(number))\u{202F}\(unit.rawValue)</weight>" : "<weight/>"
                xml += "<log><date>\(date[0])</date><workout>\(escaped(workout.title))</workout><time>\(date[1])</time>"
                    + "<exercise>\(escaped(exerciseName(set.exerciseID)))</exercise><type>default</type><reps>\(set.reps)</reps>"
                    + "\(weight)<notes/><skipped>Nein</skipped></log>"
            }
        }
        return (xml + "</logs>").data(using: .utf16) ?? Data() // UTF-16 with a byte order mark, as GymBook writes it
    }
}

private func escaped(_ text: String) -> String {
    text.replacing("&", with: "&amp;").replacing("<", with: "&lt;").replacing(">", with: "&gt;")
}
