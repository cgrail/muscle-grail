import CloudKit
import CoreData
import Foundation
import SwiftData

public enum Store {
    /// Permanent: CloudKit containers can't be deleted or renamed once created.
    public static let cloudKitContainer = "iCloud.de.grails.musclegrail"

    /// The app's stores, synced through CloudKit. Tests pass `inMemory` or a file `url`, which don't sync.
    public static func makeContainer(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: CurrentSchema.self), migrationPlan: MigrationPlan.self,
            configurations: configurations(CurrentSchema.self, inMemory: inMemory, url: url)
        )
    }

    /// Gym data and the catalog live in separate stores of one container: the gym data stays small,
    /// and the catalog's photos sync on their own. With a `url`, the catalog's file sits next to it.
    static func configurations(_ layout: any StoreLayout.Type, inMemory: Bool = false, url: URL? = nil) -> [ModelConfiguration] {
        let stores = [("Gym", layout.gymModels, url), ("Catalog", layout.catalogModels, url?.appendingPathExtension("catalog"))]
        return stores.map { name, models, url in
            if let url { return ModelConfiguration(name, schema: Schema(models), url: url, cloudKitDatabase: .none) }
            return ModelConfiguration(
                name, schema: Schema(models), isStoredInMemoryOnly: inMemory, cloudKitDatabase: inMemory ? .none : .private(cloudKitContainer)
            )
        }
    }
}

/// One failed setup, import or export: when, which, and all CloudKit or Core Data said about it.
public struct SyncFailure: Identifiable, Sendable {
    public let id = UUID()
    public let date: Date
    public let kind: String
    public let details: String
}

/// SwiftData syncs through NSPersistentCloudKitContainer, which reports every setup, import and export here.
/// There is no "sync now": the system picks when to import and export (TN3163), so this says what happened and what still waits.
@MainActor @Observable public final class SyncMonitor {
    public static let shared = SyncMonitor()

    public private(set) var lastSync: Date?
    /// Kept per store and per setup, import and export: the gym data and the catalog sync apart, and a download that
    /// went fine says nothing about an upload that failed. One success mustn't hide another failure.
    public var lastError: String? { errors.values.sorted().first }
    private var errors: [String: String] = [:]
    /// The latest failed setups, imports and exports since launch, newest first, in full, so the About section can show what went wrong.
    public private(set) var failures: [SyncFailure] = []
    private var running: Set<UUID> = []
    /// When this device last saved a change, and when the last finished export started: it took everything saved before.
    /// Both outlast a relaunch, since the watch app can be killed between sets.
    // shortcut: one date for both stores, so a gym export also clears a catalog save; track per store if that shows.
    private var changed = Date.distantPast
    private var exported = Date.distantPast
    /// Plans and exercises saved here, by store and `key`, with when, until an export of their store takes them. Outlasts a relaunch too.
    private var unsent: [String: [String: Date]] = [:]
    private let defaults: UserDefaults

    /// An import or export is running.
    public var syncing: Bool { !running.isEmpty }
    /// Changes saved here that no export has taken yet, which "Synced" alone would hide.
    public var waitingToUpload: Bool { changed > exported }

    /// Whether an export took every change saved here to `plan` and its exercises: until one does, no other device has them.
    public func inICloud(_ plan: Plan) -> Bool {
        let ids = [plan.persistentModelID] + (plan.items ?? []).map(\.persistentModelID)
        return ids.allSatisfy { unsent[$0.storeIdentifier ?? ""]?[Self.key($0)] == nil }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lastSync = defaults.object(forKey: "lastSync") as? Date
        changed = defaults.object(forKey: "lastChange") as? Date ?? .distantPast
        exported = defaults.object(forKey: "lastExport") as? Date ?? .distantPast
        unsent = defaults.dictionary(forKey: "unsentPlans") as? [String: [String: Date]] ?? [:]
        _ = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
            let (id, finished, isSync, error) = (event.identifier, event.endDate != nil, event.type != .setup, event.error.map(Self.message))
            let (exportStart, store) = (event.type == .export ? event.startDate : nil, event.storeIdentifier)
            let details = event.error.map(Self.details)
            MainActor.assumeIsolated {
                self.update(id: id, finished: finished, isSync: isSync, error: error, details: details, exportStart: exportStart, store: store)
            }
        }
        // On the saving thread, so a save off the main actor never waits for it.
        _ = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { note in
            guard Self.changes(note) else { return }
            let (date, plans) = (Date.now, Self.plans(note))
            Task { @MainActor in self.saved(at: date, plans: plans) }
        }
    }

    /// Whether a save changed anything: only then is there something to export.
    nonisolated static func changes(_ save: Notification) -> Bool {
        [ModelContext.NotificationKey.insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers].contains {
            (save.userInfo?[$0.rawValue] as? any Collection)?.isEmpty == false
        }
    }

    /// The plans and exercises a save inserted or changed. Removing an exercise changes its plan too.
    nonisolated static func plans(_ save: Notification) -> [PersistentIdentifier] {
        [ModelContext.NotificationKey.insertedIdentifiers, .updatedIdentifiers]
            .flatMap { save.userInfo?[$0.rawValue] as? [PersistentIdentifier] ?? [] }
            .filter { ["Plan", "PlanItem"].contains($0.entityName) }
    }

    /// A model's identifier as text, to compare with a remembered one: a decoded `PersistentIdentifier` never equals the store's own.
    nonisolated static func key(_ id: PersistentIdentifier) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(id)).map { String(decoding: $0, as: UTF8.self) } ?? "\(id)"
    }

    /// Core Data's CloudKit errors only say "The operation couldn't be completed", so the one users can fix gets words.
    nonisolated static func message(_ error: any Error) -> String {
        let error = error as NSError
        // 134400: no iCloud account on this device. Core Data has no public constant for it.
        if error.domain == NSCocoaErrorDomain, error.code == 134400 { return String(localized: "Sign in to iCloud to sync", bundle: .module) }
        // A partial failure only says "Failed to modify some records". In an atomic batch, the record that failed says why;
        // the others only say the batch failed.
        if let cause = refused(error).values.first { return message(cause) }
        return error.localizedDescription
    }

    /// What a failed sync says in full, with codes and server messages: each record a partial failure refused, else the error.
    nonisolated static func details(_ error: any Error) -> String {
        let error = error as NSError
        let records = refused(error)
        return records.isEmpty ? "\(error)" : records.prefix(5).map { "\($0.key)\n\($0.value)" }.joined(separator: "\n\n")
    }

    /// The records a partial failure refused, without those that only say their atomic batch failed.
    nonisolated static func refused(_ error: NSError) -> [AnyHashable: any Error] {
        (error.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: any Error] ?? [:])
            .filter { ($0.value as NSError).code != CKError.batchRequestFailed.rawValue }
    }

    /// `exportStart` is when an export began, so a finished one takes every change saved before it. `store` is the store's identifier.
    /// `details` is all the error says, for the log.
    func update(id: UUID, finished: Bool, isSync: Bool, error: String?, details: String? = nil, exportStart: Date? = nil, store: String = "") {
        guard finished else { running.insert(id); return }
        running.remove(id)
        let kind = exportStart != nil ? "export" : isSync ? "import" : "setup"
        errors[store + " " + kind] = error
        if let error { failures = Array(([SyncFailure(date: .now, kind: kind, details: details ?? error)] + failures).prefix(20)) }
        if isSync, error == nil {
            lastSync = .now
            defaults.set(lastSync, forKey: "lastSync")
            if let exportStart, let saved = unsent[store] {
                // The store's identifier is the one in its models' identifiers, so an export of the catalog leaves plans waiting.
                var waiting = unsent
                waiting[store] = saved.filter { $0.value > exportStart }
                remember(waiting)
            }
            if let exportStart, exportStart > exported {
                exported = exportStart
                defaults.set(exported, forKey: "lastExport")
            }
        }
    }

    func saved(at date: Date, plans: [PersistentIdentifier] = []) {
        var waiting = unsent
        for id in plans {
            let (store, key) = (id.storeIdentifier ?? "", Self.key(id))
            waiting[store, default: [:]][key] = max(waiting[store]?[key] ?? date, date)
        }
        if !plans.isEmpty { remember(waiting) }
        guard date > changed else { return }
        changed = date
        defaults.set(changed, forKey: "lastChange")
    }

    private func remember(_ unsent: [String: [String: Date]]) {
        self.unsent = unsent
        defaults.set(unsent, forKey: "unsentPlans")
    }

    /// Gives a background wake-up time to sync: returns once no import or export is running, or after `timeout`.
    /// `settle` covers a fresh launch, which needs a moment before its first import starts.
    public func waitUntilIdle(timeout: Duration = .seconds(20), settle: Duration = .seconds(2)) async {
        let deadline = ContinuousClock.now + timeout
        try? await Task.sleep(for: settle)
        while !running.isEmpty, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(500))
        }
    }
}
