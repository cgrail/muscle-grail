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

    @Test func deletingTheLocalCopyRemovesTheStoresFiles() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "store")
        let container = try Store.makeContainer(url: url)
        makePlan(container.mainContext, "Bench")
        try container.mainContext.save()
        try Store.deleteLocalCopy(of: Store.configurations(CurrentSchema.self, url: url))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path()) == [])
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

    @Test func oneStoresSuccessKeepsTheOthersError() {
        sync.update(id: UUID(), finished: true, isSync: true, error: "Quota", store: "Gym")
        sync.update(id: UUID(), finished: true, isSync: true, error: nil, store: "Catalog")
        #expect(sync.lastError == "Quota")
    }

    @Test func importKeepsAFailedExportsError() {
        sync.update(id: UUID(), finished: true, isSync: true, error: "Quota", exportStart: .now, store: "Gym")
        sync.update(id: UUID(), finished: true, isSync: true, error: nil, store: "Gym")
        #expect(sync.lastError == "Quota")
    }

    @Test func exportThatWorksClearsTheFailedOnesError() {
        sync.update(id: UUID(), finished: true, isSync: true, error: "Quota", exportStart: .now, store: "Gym")
        sync.update(id: UUID(), finished: true, isSync: true, error: nil, exportStart: .now, store: "Gym")
        #expect(sync.lastError == nil)
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

    @Test func runningSyncShowsAsSyncing() {
        sync.update(id: UUID(), finished: false, isSync: true, error: nil)
        #expect(sync.syncing)
    }

    @Test func savedChangeWaitsForUpload() async throws {
        let container = try Store.makeContainer(inMemory: true)
        makePlan(container.mainContext, "Bench")
        try container.mainContext.save()
        let deadline = ContinuousClock.now + .seconds(30) // the save reaches the monitor through the main actor
        while !sync.waitingToUpload, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(sync.waitingToUpload)
    }

    @Test func changeWaitingForUploadIsRememberedAcrossLaunches() {
        sync.saved(at: .now)
        #expect(SyncMonitor(defaults: prefs.defaults).waitingToUpload)
    }

    @Test func saveWithoutChangesHasNothingToUpload() {
        let save = Notification(name: ModelContext.didSave, userInfo: [ModelContext.NotificationKey.insertedIdentifiers.rawValue: [PersistentIdentifier]()])
        #expect(!SyncMonitor.changes(save))
    }

    @Test func exportTakesTheChangesSavedBeforeIt() {
        let save = Date.now
        sync.saved(at: save)
        sync.update(id: UUID(), finished: true, isSync: true, error: nil, exportStart: save + 1)
        #expect(!sync.waitingToUpload)
    }

    @Test func changeSavedAfterTheExportStartedStillWaits() {
        let save = Date.now
        sync.saved(at: save)
        sync.update(id: UUID(), finished: true, isSync: true, error: nil, exportStart: save - 1)
        #expect(sync.waitingToUpload)
    }

    @Test func savedPlanWaitsForUpload() async throws {
        let container = try Store.makeContainer(inMemory: true)
        let plan = try await savedPlan(in: container)
        #expect(!sync.inICloud(plan))
    }

    @Test func exportOfItsStoreTakesThePlan() async throws {
        let container = try Store.makeContainer(inMemory: true)
        let plan = try await savedPlan(in: container)
        try export(plan)
        #expect(sync.inICloud(plan))
    }

    @Test func exportOfTheOtherStoreLeavesThePlanWaiting() async throws {
        let container = try Store.makeContainer(inMemory: true)
        let plan = try await savedPlan(in: container)
        sync.update(id: UUID(), finished: true, isSync: true, error: nil, exportStart: .now + 1, store: "Catalog")
        #expect(!sync.inICloud(plan))
    }

    @Test func planWaitsWhileOneOfItsExercisesDoes() async throws {
        let container = try Store.makeContainer(inMemory: true)
        let plan = try await savedPlan(in: container)
        try export(plan)
        sync.saved(at: .now + 2, plans: [plan.sortedItems[0].persistentModelID])
        #expect(!sync.inICloud(plan))
    }

    @Test func removedExerciseLeavesItsPlanWaiting() async throws {
        let container = try Store.makeContainer(inMemory: true)
        let plan = try await savedPlan(in: container)
        try export(plan)
        container.mainContext.deleteExercise(plan.sortedItems[0])
        try container.mainContext.save()
        let deadline = ContinuousClock.now + .seconds(30)
        while sync.inICloud(plan), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!sync.inICloud(plan))
    }

    @Test func waitingPlanIsRememberedAcrossLaunches() async throws {
        let container = try Store.makeContainer(inMemory: true)
        let plan = try await savedPlan(in: container)
        #expect(!SyncMonitor(defaults: prefs.defaults).inICloud(plan))
    }

    /// A saved plan with one exercise, once the save has reached the monitor through the main actor.
    func savedPlan(in container: ModelContainer) async throws -> Plan {
        let plan = makePlan(container.mainContext, "Bench")
        try container.mainContext.save()
        let deadline = ContinuousClock.now + .seconds(30)
        while sync.inICloud(plan), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        return plan
    }

    /// A finished export of the plan's store that started after every save so far.
    func export(_ plan: Plan) throws {
        let store = try #require(plan.persistentModelID.storeIdentifier)
        sync.update(id: UUID(), finished: true, isSync: true, error: nil, exportStart: .now + 1, store: store)
    }

    @Test func failedExportLeavesChangesWaiting() {
        let save = Date.now
        sync.saved(at: save)
        sync.update(id: UUID(), finished: true, isSync: true, error: "Offline", exportStart: save + 1)
        #expect(sync.waitingToUpload)
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
