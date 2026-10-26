import CoreData
import Foundation
import SwiftData
import Testing
@testable import Core

struct StoreTests {
    @Test func bothStoresSyncThroughThePermanentContainer() {
        let stores = Store.configurations(CurrentSchema.self)
        #expect(stores.map(\.name) == ["Gym", "Catalog"])
        #expect(stores.allSatisfy { $0.cloudKitContainerIdentifier == "iCloud.de.grails.musclegrail" })
    }

    @Test func testStoresDontSync() {
        let url = URL.temporaryDirectory.appending(path: "x.store")
        let stores = Store.configurations(CurrentSchema.self, inMemory: true) + Store.configurations(CurrentSchema.self, url: url)
        #expect(stores.allSatisfy { $0.cloudKitContainerIdentifier == nil })
    }
}

@MainActor struct OpenStoreTests {
    @Test func storeThatDoesntOpenSaysWhy() {
        let store = OpenStore { throw CocoaError(.fileReadCorruptFile) }
        #expect(store.container == nil && store.error != nil)
    }

    @Test func storeOpensAgainOnceFixed() {
        var broken = true
        let store = OpenStore {
            if broken { throw CocoaError(.fileReadCorruptFile) }
            return try Store.makeContainer(inMemory: true)
        }
        broken = false
        store.open()
        #expect(store.container != nil && store.error == nil)
    }

    @Test func deletingTheLocalCopyEmptiesTheStore() throws {
        let url = URL.temporaryDirectory.appending(path: "\(UUID()).store")
        do {
            let container = try Store.makeContainer(url: url)
            makePlan(container.mainContext)
            try container.mainContext.save()
        }
        try Store.deleteLocalCopy(of: Store.configurations(CurrentSchema.self, url: url))
        #expect(try Store.makeContainer(url: url).mainContext.fetchCount(FetchDescriptor<Plan>()) == 0)
    }
}

@MainActor struct SyncMonitorTests {
    let prefs = TestDefaults()
    let sync: SyncMonitor

    init() {
        sync = SyncMonitor(defaults: prefs.defaults)
    }

    @Test func finishedSyncIsRememberedAcrossLaunches() {
        sync.update(id: UUID(), finished: true, isSync: true, error: nil)
        #expect(SyncMonitor(defaults: prefs.defaults).lastSync != nil)
    }

    @Test func setupIsNotASync() {
        sync.update(id: UUID(), finished: true, isSync: false, error: nil)
        #expect(sync.lastSync == nil)
    }

    @Test func failedSyncShowsItsError() {
        sync.update(id: UUID(), finished: true, isSync: true, error: "Offline")
        #expect(sync.lastError == "Offline")
        #expect(sync.lastSync == nil)
    }

    @Test func missingICloudAccountAsksToSignIn() {
        let message = SyncMonitor.message(NSError(domain: NSCocoaErrorDomain, code: 134400))
        #expect(message == String(localized: "Sign in to iCloud to sync", bundle: .module))
    }

    @Test func otherErrorsKeepTheirDescription() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        #expect(SyncMonitor.message(error) == error.localizedDescription)
    }

    @Test func notificationWithoutAnEventChangesNothing() {
        NotificationCenter.default.post(name: NSPersistentCloudKitContainer.eventChangedNotification, object: nil)
        #expect(sync.lastSync == nil && sync.lastError == nil)
    }

    // Waits use long timeouts and check for "well before the timeout": other main-actor tests can delay any step.

    @Test func waitReturnsRightAwayWhenNothingRuns() async {
        let start = ContinuousClock.now
        await sync.waitUntilIdle(timeout: .seconds(30), settle: .zero)
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test func waitReturnsOnceTheRunningSyncFinishes() async {
        let id = UUID()
        sync.update(id: id, finished: false, isSync: true, error: nil)
        Task { // finishes after the wait has polled at least once
            try? await Task.sleep(for: .seconds(1))
            sync.update(id: id, finished: true, isSync: true, error: nil)
        }
        let start = ContinuousClock.now
        await sync.waitUntilIdle(timeout: .seconds(30), settle: .zero)
        #expect(ContinuousClock.now - start < .seconds(10))
    }

    @Test func waitGivesUpAtTheTimeout() async {
        sync.update(id: UUID(), finished: false, isSync: true, error: nil)
        let start = ContinuousClock.now
        await sync.waitUntilIdle(timeout: .zero, settle: .zero)
        #expect(ContinuousClock.now - start < .seconds(5))
    }
}
