import Foundation
import SwiftData
import Testing
@testable import Core

/// The iPhone and the watch, each with its own store: what the watch hands the phone over Bluetooth, and how the phone's
/// copies go once iCloud brings the watch's own records. `WCSession` itself is checked by acceptance test M.
@MainActor struct WatchLinkTests {
    let phoneStore = try! Store.makeContainer(inMemory: true)
    let watchStore = try! Store.makeContainer(inMemory: true)
    var phone: ModelContext { phoneStore.mainContext }
    var watch: ModelContext { watchStore.mainContext }

    /// A Bench plan made on the phone, which the watch has through iCloud. Returns the watch's.
    func plan() throws -> Plan {
        makePlan(phone, "Bench")
        try phone.save()
        try phone.replay(into: watch)
        try watch.save()
        return try #require(watch.fetch(FetchDescriptor<Plan>()).first)
    }

    /// A workout on the watch, with a set of Bench at 60 kg for each of `reps`.
    @discardableResult
    func train(_ reps: Int...) throws -> Workout {
        let workout = try watch.startWorkout(plan())
        for rep in reps { watch.log("Bench", reps: rep, weightKg: 60, in: workout) }
        return workout
    }

    /// Hands the watch's training to the phone, as the link does. Returns the copies it made there.
    @discardableResult
    func link() throws -> [LinkCopy] {
        try phone.receiveLinked(watch.linkOutgoing(after: .distantPast))
    }

    /// What iCloud brings the phone later: the watch's own workouts, sets and actions, as records of their own with the same ids.
    func iCloud() throws {
        for theirs in try watch.fetch(FetchDescriptor<Workout>()) {
            let workout = Workout()
            (workout.id, workout.start, workout.end, workout.healthKitID) = (theirs.id, theirs.start, theirs.end, theirs.healthKitID)
            phone.insert(workout)
            workout.plan = theirs.plan.flatMap { phone.plan($0.id) }
            for logged in theirs.sets ?? [] {
                let set = LoggedSet(exerciseID: logged.exerciseID, reps: logged.reps, weightKg: logged.weightKg)
                (set.id, set.date) = (logged.id, logged.date)
                phone.insert(set)
                set.workout = workout
            }
        }
        for theirs in try watch.fetch(FetchDescriptor<Action>()) {
            let action = Action()
            (action.id, action.date, action.version, action.payload) = (theirs.id, theirs.date, theirs.version, theirs.payload)
            phone.insert(action)
        }
        try phone.save()
    }

    /// The phone's history: each workout's reps of Bench, newest first.
    func phoneHistory() throws -> [[Int]] {
        try phone.fetch(Workout.history).map { $0.sets(of: "Bench").map(\.reps) }
    }

    @Test func onlyTrainingGoesOver() throws {
        let plan = makePlan(phone, "Bench")
        phone.log("Bench", reps: 10, weightKg: 60, in: phone.startWorkout(plan))
        #expect(try phone.linkOutgoing(after: .distantPast).map { "\($0.change)".prefix { $0 != "(" } } == ["startWorkout", "logSet"])
    }

    @Test func onlyWhatCameAfterTheLastSendGoesOver() throws {
        let workout = try train(10)
        let sent = try #require(watch.linkOutgoing(after: .distantPast).last).date
        watch.log("Bench", reps: 8, weightKg: 60, in: workout)
        #expect(try watch.linkOutgoing(after: sent).count == 1)
    }

    @Test func aWatchSetShowsOnThePhoneRightAway() throws {
        try train(8)
        try link()
        #expect(try phoneHistory() == [[8]])
    }

    @Test func aChangeThatIsHereAlreadyIsLeftOut() throws {
        try train(8)
        try link()
        try link()
        #expect(try phone.fetchCount(FetchDescriptor<LoggedSet>()) == 1)
    }

    @Test func whatTheLinkBroughtDoesNotGoBack() throws {
        try train(8)
        let brought = try Set(link().filter { $0.kind == .action }.map(\.id))
        #expect(try phone.linkOutgoing(after: .distantPast, skipping: brought).isEmpty)
    }

    @Test func theCopiesGoWhenICloudBringsTheOriginals() throws {
        try train(8, 6)
        let copies = try link()
        try iCloud()
        _ = try phone.dropCopies(copies)
        let actions = try phone.fetch(FetchDescriptor<Action>()).map(\.id)
        #expect(try snapshot(phone) == snapshot(watch))
        #expect(actions.count == Set(actions).count)
    }

    @Test func aCopyWaitsForItsOriginal() throws {
        try train(8)
        let copies = try link()
        #expect(try Set(phone.dropCopies(copies)) == Set(copies))
    }

    @Test func setsLoggedHereMoveToTheOriginalWorkout() throws {
        try train(8)
        let copies = try link()
        phone.log("Bench", reps: 5, weightKg: 60, in: try #require(phone.fetch(Workout.unfinished).first))
        try iCloud()
        _ = try phone.dropCopies(copies)
        #expect(try phoneHistory() == [[8, 5]])
    }

    @Test func aFinishOnlyTheCopyHasCarriesOver() throws {
        try train(8)
        let copies = try link()
        phone.finish(try #require(phone.fetch(Workout.unfinished).first))
        try iCloud()
        _ = try phone.dropCopies(copies)
        #expect(!phone.isTraining)
    }

    @Test func aCopyDeletedHereWaitsNoMore() throws {
        try train(8)
        let copies = try link()
        phone.undo(try #require(phone.fetch(FetchDescriptor<LoggedSet>()).first))
        #expect(try !phone.dropCopies(copies).contains { $0.kind == .set })
    }
}
