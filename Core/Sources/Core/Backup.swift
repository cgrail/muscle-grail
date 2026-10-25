import Foundation
import SwiftData

/// Both action logs as one JSON file. `replay` can rebuild the whole model from them, on any later version.
public enum Backup {
    public static let fileName = "Muscle Grail Backup.json"

    struct Entry: Codable, Equatable {
        var id: UUID
        var date: Date
        var version: Int
        /// The `Change` as recorded, so changes from newer versions are kept too.
        var payload: Data

        init(_ record: some ChangeRecord) {
            (id, date, version, payload) = (record.id, record.date, record.version, record.payload)
        }
    }

    struct File: Codable {
        var gym: [Entry]
        var catalog: [Entry]
    }

    /// Writes the backup into `folder`, replacing the last one, from a context of its own so it can run off the main actor.
    /// An empty log writes nothing: a fresh install that hasn't synced yet must not overwrite a good backup.
    public static func write(_ container: ModelContainer, to folder: URL) throws {
        let context = ModelContext(container)
        let file = File(
            gym: try context.fetch(FetchDescriptor<Action>(sortBy: [SortDescriptor(\.date)])).map(Entry.init),
            catalog: try context.fetch(FetchDescriptor<CatalogAction>(sortBy: [SortDescriptor(\.date)])).map(Entry.init)
        )
        guard !file.gym.isEmpty || !file.catalog.isEmpty else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        try encoder.encode(file).write(to: folder.appending(path: fileName), options: .atomic)
    }
}
