#if DEBUG
import CloudKit
import Core
import CoreData
import SwiftData

/// Launched with `-initializeCloudKitSchema` (an argument to tick in the MuscleGrail scheme), a debug build creates every record
/// type and field of the model and of the `Partner` zone in CloudKit's Development schema, then quits. Syncing creates only the
/// fields it uploads a value for, and Production refuses records with a type or field its schema lacks, so deploy the schema to
/// Production after this run.
enum CloudKitSchema {
    static func initializeIfAsked() {
        guard CommandLine.arguments.contains("-initializeCloudKitSchema") else { return }
        do {
            try initialize()
            print("CloudKit schema of the model initialized in Development.")
        } catch {
            print("CloudKit schema of the model not initialized: \(error)")
        }
        // Detached and waited for here: the main actor is blocked until it's done.
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                try await initializePartner()
                print("CloudKit schema of the Partner zone initialized in Development.")
            } catch {
                print("CloudKit schema of the Partner zone not initialized: \(error)")
            }
            done.signal()
        }
        done.wait()
        print("Deploy the schema to Production in the CloudKit Console.")
        exit(0)
    }

    /// Through a throwaway store, so the app's own stores and their sync status stay out of it. Record types belong to the
    /// container, not to a store, so one store with every model covers both of the app's.
    private static func initialize() throws {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: CurrentSchema.models) else { throw CocoaError(.featureUnsupported) }
        let store = NSPersistentStoreDescription(url: .temporaryDirectory.appending(path: "\(UUID().uuidString).store"))
        store.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Store.cloudKitContainer)
        store.shouldAddStoreAsynchronously = false
        let container = NSPersistentCloudKitContainer(name: "CloudKitSchema", managedObjectModel: model)
        container.persistentStoreDescriptions = [store]
        container.loadPersistentStores { _, error in if let error { print("CloudKit schema store didn't load: \(error)") } }
        try container.initializeCloudKitSchema()
    }

    /// The `Partner` zone's types come from `CKSyncEngine`'s records, not the model: one of each with every field set, and a
    /// zone share, saved in a throwaway zone that is deleted after.
    private nonisolated static func initializePartner() async throws {
        let database = CKContainer(identifier: Store.cloudKitContainer).privateCloudDatabase
        let zone = CKRecordZone.ID(zoneName: "Schema")
        _ = try await retrying { try await database.save(CKRecordZone(zoneID: zone)) }
        let change = PartnerChange(id: UUID(), date: .now, change: .renamePlan(id: UUID(), name: "Schema"), batch: UUID(), sets: 1, reps: 1, name: "Schema")
        let records = [PartnerRecords.plan(UUID(), in: zone), PartnerRecords.settings(allPlans: true, in: zone), change.record(in: zone), CKShare(recordZoneID: zone)]
        let saved = try await retrying { try await database.modifyRecords(saving: records, deleting: []) }
        _ = try await retrying { try await database.deleteRecordZone(withID: zone) }
        for result in saved.saveResults.values { _ = try result.get() }
    }

    /// The model's run just before uploads a burst, and CloudKit throttles what follows ("Request Rate Limited", HTTP 429).
    /// A throttled call waits as long as CloudKit asks, then tries again, up to five times.
    private nonisolated static func retrying<T>(_ call: () async throws -> T) async throws -> T {
        for _ in 1..<5 {
            do {
                return try await call()
            } catch let error as CKError {
                guard let wait = error.retryAfterSeconds else { throw error }
                print("CloudKit throttles the Partner zone's schema run: trying again in \(Int(wait.rounded(.up))) s.")
                try await Task.sleep(for: .seconds(wait))
            }
        }
        return try await call()
    }
}
#endif
