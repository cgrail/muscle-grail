import CoreData
import Foundation
import SwiftData

public enum Store {
    /// Permanent: CloudKit containers can't be deleted or renamed once created.
    public static let cloudKitContainer = "iCloud.de.grails.musclegrail"

    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let config = ModelConfiguration(
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: inMemory ? .none : .private(cloudKitContainer)
        )
        return try ModelContainer(for: Plan.self, PlanItem.self, Workout.self, LoggedSet.self, configurations: config)
    }
}

/// SwiftData syncs through NSPersistentCloudKitContainer, which reports every setup, import and export here.
@MainActor @Observable public final class SyncMonitor {
    public static let shared = SyncMonitor()

    public private(set) var lastSync = UserDefaults.standard.object(forKey: "lastSync") as? Date
    public private(set) var lastError: String?
    private var running: Set<UUID> = []

    private init() {
        _ = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
            let (id, finished, isSync, error) = (event.identifier, event.endDate != nil, event.type != .setup, event.error?.localizedDescription)
            MainActor.assumeIsolated { self.update(id: id, finished: finished, isSync: isSync, error: error) }
        }
    }

    private func update(id: UUID, finished: Bool, isSync: Bool, error: String?) {
        guard finished else { running.insert(id); return }
        running.remove(id)
        lastError = error
        if isSync, error == nil {
            lastSync = .now
            UserDefaults.standard.set(lastSync, forKey: "lastSync")
        }
    }

    /// Gives a background wake-up time to sync: returns once no import or export is running, or after `timeout`.
    public func waitUntilIdle(timeout: Duration = .seconds(20)) async {
        let deadline = ContinuousClock.now + timeout
        try? await Task.sleep(for: .seconds(2)) // a fresh launch needs a moment before its first import starts
        while !running.isEmpty, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(500))
        }
    }
}
