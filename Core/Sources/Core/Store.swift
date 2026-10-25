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

/// SwiftData syncs through NSPersistentCloudKitContainer, which reports every setup, import and export here.
@MainActor @Observable public final class SyncMonitor {
    public static let shared = SyncMonitor()

    public private(set) var lastSync: Date?
    public private(set) var lastError: String?
    private var running: Set<UUID> = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lastSync = defaults.object(forKey: "lastSync") as? Date
        _ = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
            let (id, finished, isSync, error) = (event.identifier, event.endDate != nil, event.type != .setup, event.error?.localizedDescription)
            MainActor.assumeIsolated { self.update(id: id, finished: finished, isSync: isSync, error: error) }
        }
    }

    func update(id: UUID, finished: Bool, isSync: Bool, error: String?) {
        guard finished else { running.insert(id); return }
        running.remove(id)
        lastError = error
        if isSync, error == nil {
            lastSync = .now
            defaults.set(lastSync, forKey: "lastSync")
        }
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
