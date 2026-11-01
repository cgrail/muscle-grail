import CryptoKit
import Foundation
import SwiftData

/// What GymBook gives to take along: its log export, an XML file with a `<log>` per set, the newest workout first, or its
/// full backup (`backup`), which has its plans too. Importing either brings the history and plans over from GymBook;
/// exporting writes the history back in the log export's format.
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

    /// A plan, named like the workouts trained from it.
    public struct Plan: Equatable, Sendable {
        public var name: String
        public var exercises: [Planned] = []
        /// Put away in GymBook, which keeps an archived plan for its history.
        public var archived = false
    }

    /// An exercise of a plan with its sets, reps and weight.
    public struct Planned: Equatable, Sendable {
        public var exercise: String
        public var sets: Int
        public var reps: Int?
        public var weightKg = 0.0
        public var unit = WeightUnit.kg
    }

    /// A workout: the sets of one day under one workout name.
    public struct Session: Sendable {
        /// The day and workout name, which its id and its sets' come from.
        let key: String
        /// Its sets as listed, the skipped ones too.
        public let logs: [Log]
        public var plan: String { logs[0].workout }
        /// The sets done, in the order they were.
        public var done: [Log] { logs.filter { !$0.skipped }.sorted { $0.date < $1.date } }
        var id: UUID { GymBook.id("workout \(key)") }
    }

    /// What a GymBook file holds. Cardio has no reps, so it is in `logs` only.
    public struct File: Sendable {
        public let logs: [Log]
        /// The workouts with a set done, the newest first.
        public let sessions: [Session]
        /// The backup's plans, the active ones first; for the log export, a plan per workout name from its newest workout.
        public let plans: [Plan]
        /// The English name GymBook keeps beside the one it shows, like `legPresses`: only the backup has them.
        public let englishNames: [String: String]

        init(logs: [Log], plans: [Plan]? = nil, englishNames: [String: String] = [:]) {
            self.logs = logs
            sessions = Dictionary(grouping: logs.filter { $0.reps != nil }, by: GymBook.session)
                .map { Session(key: $0.key, logs: $0.value) }.filter { !$0.done.isEmpty }.sorted { $0.logs[0].date > $1.logs[0].date }
            self.plans = plans ?? sessions.reduce(into: []) { plans, session in
                guard !plans.contains(where: { $0.name == session.plan }) else { return }
                let names = session.logs.map(\.exercise).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                plans.append(Plan(name: session.plan, exercises: names.map { name in
                    let sets = session.logs.filter { $0.exercise == name } // skipped ones too: they were planned
                    return Planned(exercise: name, sets: sets.count, reps: sets.last!.reps, weightKg: sets.last!.weightKg, unit: sets.last!.unit)
                }))
            }
            self.englishNames = englishNames
        }

        /// The exercises with sets, done or planned, to map to exercises here before importing.
        public var exercises: [String] {
            Set(sessions.flatMap { $0.logs.map(\.exercise) } + plans.flatMap { $0.exercises.map(\.exercise) }).sorted()
        }
    }

    /// What `data` holds: GymBook's log export or its full backup. A file that is neither throws.
    public static func read(_ data: Data) throws -> File {
        if data.starts(with: Data("SQLite format 3\u{0}".utf8)) { return try backup(data) }
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse(), reader.isLogs else { throw parser.parserError ?? CocoaError(.fileReadCorruptFile) }
        return File(logs: reader.logs)
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
