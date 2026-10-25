import CoreData
import Foundation
import Testing
@testable import Core

struct StoreTests {
    @Test func appStoreSyncsThroughThePermanentContainer() {
        #expect(Store.configuration().cloudKitContainerIdentifier == "iCloud.de.grails.musclegrail")
    }

    @Test func testStoresDontSync() {
        #expect(Store.configuration(inMemory: true).cloudKitContainerIdentifier == nil)
        #expect(Store.configuration(url: .temporaryDirectory.appending(path: "x.store")).cloudKitContainerIdentifier == nil)
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

    @Test func waitReturnsOnceTheRunningSyncFinishes() async throws {
        let id = UUID()
        sync.update(id: id, finished: false, isSync: true, error: nil)
        let waiting = Task { await sync.waitUntilIdle(timeout: .seconds(30), settle: .zero) }
        try await Task.sleep(for: .milliseconds(50)) // let the wait start polling
        sync.update(id: id, finished: true, isSync: true, error: nil)
        let start = ContinuousClock.now
        await waiting.value
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test func waitGivesUpAtTheTimeout() async {
        sync.update(id: UUID(), finished: false, isSync: true, error: nil)
        let start = ContinuousClock.now
        await sync.waitUntilIdle(timeout: .zero, settle: .zero)
        #expect(ContinuousClock.now - start < .seconds(5))
    }
}
