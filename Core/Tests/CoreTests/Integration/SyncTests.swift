import Foundation
import SwiftData
import Testing
@testable import Core

/// CloudKit doesn't run under `swift test`. Each device here is its own container on one store file, which stands in for
/// CloudKit delivering the other devices' records into the local store. Real sync is acceptance tests A–C in PLAN.md.
@MainActor struct SyncTests {
    @Test func watchWorkoutLoggedOfflineReachesThePhone() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func device() throws -> ModelContainer { try Store.makeContainer(url: folder.appending(path: "store")) }

        let mac = try device()
        makePlan(mac.mainContext, "Bench")
        try mac.mainContext.save() // the Mac autosaves

        let phone = try device()
        let phonePlan = try #require(phone.mainContext.fetch(FetchDescriptor<Plan>()).first)
        let lastWeek = phone.mainContext.startWorkout(phonePlan)
        phone.mainContext.log("Bench", reps: 10, weightKg: 55, in: lastWeek)
        phone.mainContext.finish(lastWeek)

        let watch = try device()
        let today = watch.mainContext.startWorkout(try #require(watch.mainContext.fetch(FetchDescriptor<Plan>()).first))
        watch.mainContext.log("Bench", reps: 8, weightKg: 60, in: today)
        watch.mainContext.log("Bench", reps: 6, weightKg: 60, in: today)
        watch.mainContext.finish(today)

        let history = try phone.mainContext.fetch(Workout.history)
        #expect(history.map { $0.sets(of: "Bench").map(\.reps) } == [[8, 6], [10]])
        let next = phone.mainContext.startWorkout(phonePlan)
        #expect(phone.mainContext.nextSet(for: phonePlan.sortedItems[0], in: next) == (8, 60))
    }
}
