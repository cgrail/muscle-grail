#if DEBUG
import Core
import CoreData
import SwiftData

/// Launched with `-initializeCloudKitSchema` (an argument to tick in the MuscleGrail scheme), a debug build creates every record
/// type and field of the model in CloudKit's Development schema, then quits. Syncing creates only the fields it uploads a value
/// for, and Production refuses records with a type or field its schema lacks, so deploy the schema to Production after this run.
enum CloudKitSchema {
    static func initializeIfAsked() {
        guard CommandLine.arguments.contains("-initializeCloudKitSchema") else { return }
        do {
            try initialize()
            print("CloudKit schema initialized in Development. Deploy it to Production in the CloudKit Console.")
        } catch {
            print("CloudKit schema not initialized: \(error)")
        }
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
}
#endif
