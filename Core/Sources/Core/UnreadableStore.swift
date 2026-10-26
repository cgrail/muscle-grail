import CloudKit
import Foundation
import SwiftData
import SwiftUI

/// The app's store, or why it didn't open, so the apps can offer a way out instead of crashing.
@MainActor @Observable public final class OpenStore {
    public private(set) var container: ModelContainer?
    public private(set) var error: String?
    private let make: () throws -> ModelContainer

    public init(_ make: @escaping () throws -> ModelContainer = { try Store.makeContainer() }) {
        self.make = make
        open()
    }

    /// Opens the store again, after the user deleted what kept it from opening.
    public func open() {
        do {
            container = try make()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

public extension Store {
    /// Deletes this device's copy of the stores. New ones fill again from iCloud.
    static func deleteLocalCopy() throws {
        try deleteLocalCopy(of: configurations(CurrentSchema.self))
    }

    /// Deletes the app's data in iCloud, every zone of its private database, so every device starts empty.
    static func deleteICloudData() async throws {
        let database = CKContainer(identifier: cloudKitContainer).privateCloudDatabase
        let zones = try await database.allRecordZones().map(\.zoneID).filter { $0 != CKRecordZone.default().zoneID }
        guard !zones.isEmpty else { return }
        for result in try await database.modifyRecordZones(saving: [], deleting: zones).deleteResults.values { try result.get() }
    }
}

extension Store {
    /// Removes each store's files: the database, its journal (`-wal`, `-shm`) and its folder of large data (`.<name>_SUPPORT`).
    /// Nothing has them open, since the store didn't open.
    static func deleteLocalCopy(of stores: [ModelConfiguration]) throws {
        let files = FileManager.default
        for store in stores {
            let folder = store.url.deletingLastPathComponent()
            let support = ".\(store.url.deletingPathExtension().lastPathComponent)_SUPPORT"
            for name in try files.contentsOfDirectory(atPath: folder.path()) where name.hasPrefix(store.url.lastPathComponent) || name == support {
                try files.removeItem(at: folder.appending(path: name))
            }
        }
    }
}

/// Shown instead of the app when this version can't read the data on the device: download it again, or start from scratch.
public struct UnreadableStore: View {
    let store: OpenStore
    @State private var confirming = false
    @State private var working = false
    @State private var failure: String?

    public init(_ store: OpenStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                Text("This version can't read the data on this device.", bundle: .module).font(.headline)
                Text(verbatim: failure ?? store.error ?? "").font(.caption).foregroundStyle(.secondary)
                Button { fix { try Store.deleteLocalCopy() } } label: { Text("Download again", bundle: .module) }
                    .buttonStyle(.borderedProminent)
                Button(role: .destructive) { confirming = true } label: { Text("Start from scratch", bundle: .module) }
            }
            .multilineTextAlignment(.center)
            .padding()
        }
        .disabled(working)
        .confirmationDialog(Text("Start from scratch?", bundle: .module), isPresented: $confirming, titleVisibility: .visible) {
            Button(role: .destructive) {
                fix {
                    try await Store.deleteICloudData()
                    try Store.deleteLocalCopy()
                }
            } label: {
                Text("Delete everything", bundle: .module)
            }
        } message: {
            Text("This deletes your plans, workouts and exercises on every device and in iCloud. It can't be undone. A backup on the Mac can bring them back.", bundle: .module)
        }
    }

    /// Runs `deletion`, then opens the store again, or says why it failed.
    private func fix(_ deletion: @escaping @Sendable () async throws -> Void) {
        working = true
        Task {
            do {
                try await deletion()
                store.open()
            } catch {
                failure = error.localizedDescription
            }
            working = false
        }
    }
}
