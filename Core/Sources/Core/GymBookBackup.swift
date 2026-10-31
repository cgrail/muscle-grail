import Foundation
import SQLite3

extension GymBook {
    /// GymBook's full backup, its Core Data store as one SQLite file: the logs as its log export lists them, the newest
    /// workout first and each one's logs in the order they were done, and its plans, the active ones first, in GymBook's
    /// order. A log's day and time are the gym's local ones.
    static func backup(_ data: Data) throws -> File {
        var data = data
        return try data.withUnsafeMutableBytes { bytes in
            var db: OpaquePointer?
            defer { sqlite3_close(db) }
            guard sqlite3_open(":memory:", &db) == SQLITE_OK,
                  sqlite3_deserialize(db, "main", bytes.baseAddress?.assumingMemoryBound(to: UInt8.self), Int64(bytes.count),
                                      Int64(bytes.count), UInt32(SQLITE_DESERIALIZE_READONLY)) == SQLITE_OK
            else { throw CocoaError(.fileReadCorruptFile) }
            func rows(_ sql: String, _ read: (Row) -> Void) throws {
                var statement: OpaquePointer?
                defer { sqlite3_finalize(statement) }
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw CocoaError(.fileReadCorruptFile) }
                while sqlite3_step(statement) == SQLITE_ROW { read(Row(statement: statement)) }
            }
            let format = DateFormatter()
            format.locale = Locale(identifier: "en_US_POSIX")
            format.dateFormat = "yyyy-MM-dd HH:mm:ss"
            var logs: [Log] = []
            try rows("""
                SELECT l.ZDAY || ' ' || time(l.ZTIME, 'unixepoch'), w.ZNAME, e.ZNAME,
                       CASE WHEN l.ZFREQUENCYUNIT = 'x' THEN l.ZFREQUENCYVALUE END, l.ZQUANTITYVALUE, l.ZQUANTITYUNIT, l.ZSKIPPED
                FROM ZEXERCISELOG l JOIN ZWORKOUT w ON w.Z_PK = l.ZWORKOUT JOIN ZEXERCISE e ON e.Z_PK = l.ZEXERCISE
                ORDER BY l.ZDAY DESC, l.ZTIME, l.Z_PK
                """) { row in
                guard let date = row.text(0).flatMap(format.date), let workout = row.text(1), let exercise = row.text(2) else { return }
                let unit = row.text(5).flatMap(WeightUnit.init) // cardio's is km, its reps' unit minutes
                logs.append(Log(date: date, workout: workout, exercise: exercise, reps: row.int(3),
                                weightKg: unit?.kg(row.double(4)) ?? 0, unit: unit ?? .kg, skipped: row.int(6) == 1))
            }
            var plans: [Plan] = []
            var plan: Int?
            // shortcut: a plan's sets with different reps or weights come in with the most of each; GymBook's pyramids would need a row per set
            try rows("""
                SELECT w.Z_PK, w.ZNAME, w.ZARCHIVED, e.ZNAME, count(*), max(coalesce(s.ZFREQUENCYVALUEMAX, s.ZFREQUENCYVALUEMIN)),
                       max(s.ZQUANTITYVALUE), s.ZQUANTITYUNIT
                FROM ZWORKOUT w JOIN ZWORKOUTEXERCISE we ON we.ZWORKOUT = w.Z_PK JOIN ZEXERCISE e ON e.Z_PK = we.ZEXERCISE
                JOIN ZWORKOUTEXERCISESET s ON s.ZWORKOUTEXERCISE = we.Z_PK
                WHERE s.ZFREQUENCYUNIT = 'x'
                GROUP BY we.Z_PK ORDER BY coalesce(w.ZARCHIVED, 0), w.ZDISPLAYORDER, w.Z_PK, we.ZDISPLAYORDER
                """) { row in
                guard let name = row.text(1), let exercise = row.text(3) else { return }
                if row.int(0) != plan { plans.append(Plan(name: name, archived: row.int(2) == 1)) }
                plan = row.int(0)
                let unit = row.text(7).flatMap(WeightUnit.init) ?? .kg
                plans[plans.count - 1].exercises.append(Planned(exercise: exercise, sets: row.int(4) ?? 0, reps: row.int(5),
                                                                weightKg: unit.kg(row.double(6)), unit: unit))
            }
            var englishNames: [String: String] = [:]
            try rows("SELECT ZNAME, ZIDENTIFIER FROM ZEXERCISE") { row in
                if let name = row.text(0), let identifier = row.text(1) { englishNames[name] = identifier }
            }
            return File(logs: logs, plans: plans, englishNames: englishNames)
        }
    }
}

/// A row of a query, read by column.
private struct Row {
    let statement: OpaquePointer?

    func text(_ column: Int32) -> String? { sqlite3_column_text(statement, column).map { String(cString: $0) } }

    /// Nil for NULL.
    func int(_ column: Int32) -> Int? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, column))
    }

    func double(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
}
