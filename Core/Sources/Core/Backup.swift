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
        /// `Action`'s, so the history still says who made each change.
        var author: String?
        var batch: UUID?

        init(_ record: some ChangeRecord) {
            (id, date, version, payload) = (record.id, record.date, record.version, record.payload)
            if let action = record as? Action { (author, batch) = (action.author, action.batch) }
        }

        func record<R: ChangeRecord>() -> R {
            let record = R()
            (record.id, record.date, record.version, record.payload) = (id, date, version, payload)
            if let action = record as? Action { (action.author, action.batch) = (author, batch) }
            return record
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

    /// Replaces everything in the store with the backup `file`: both logs, and the model they rebuild. The deletions sync,
    /// so every device ends up with the backup. A file that doesn't read as a backup changes nothing.
    public static func restore(_ file: URL, into context: ModelContext) throws {
        let backup = try JSONDecoder().decode(File.self, from: Data(contentsOf: file))
        for model in CurrentSchema.models { try context.deleteAll(model) }
        for entry in backup.gym { context.insert(entry.record() as Action) }
        for entry in backup.catalog { context.insert(entry.record() as CatalogAction) }
        try context.replay(into: context)
        try context.save()
    }
}

private extension ModelContext {
    // One by one, not a batch delete: CloudKit mirrors what the context deletes.
    func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        for model in try fetch(FetchDescriptor<T>()) { delete(model) }
    }
}
