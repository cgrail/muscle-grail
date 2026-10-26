import Foundation
import SwiftData
import Testing
@testable import Core

/// Two people's stores, as the shared zone links them: what one changes and what the other gets.
@MainActor struct PartnerTests {
    let mine = try! Store.makeContainer(inMemory: true)
    let theirs = try! Store.makeContainer(inMemory: true)
    var me: ModelContext { mine.mainContext }
    var partner: ModelContext { theirs.mainContext }

    /// The date of the newest change here: everything up to it is sent.
    func mark() throws -> Date {
        try me.fetch(FetchDescriptor<Action>()).map(\.date).max() ?? .distantPast
    }

    /// What changed here after `after`, in the plans `shared`, as the partner gets it.
    func outgoing(after: Date = .distantPast, _ shared: Plan...) throws -> [Change] {
        try me.save()
        return try PartnerChange.outgoing(mine, after: after, shared: Set(shared.map(\.id))).map(\.change)
    }

    /// Hands that to the partner, as the zone would.
    func send(after: Date = .distantPast, _ shared: Plan...) throws {
        try me.save()
        partner.receive(try PartnerChange.outgoing(mine, after: after, shared: Set(shared.map(\.id))), from: "Me")
    }

    @Test func aSharedPlanReachesThePartnerWithItsExercises() throws {
        let plan = makePlan(me, "Bench", "Row")
        try send(plan)
        #expect(partner.plan(plan.id)?.sortedItems.map(\.exerciseID) == ["Bench", "Row"])
    }

    @Test func aPlanThatIsNotSharedStaysHere() throws {
        makePlan(me, "Bench")
        #expect(try outgoing().isEmpty)
    }

    @Test func setsRepsAndWeightsStayHere() throws {
        let plan = makePlan(me, "Bench")
        let sent = try mark()
        me.setTargets(plan.sortedItems[0], sets: 5, reps: 5, weightKg: 80)
        #expect(try outgoing(after: sent, plan).isEmpty)
    }

    @Test func theOrderOfThePlanListStaysHere() throws {
        let push = makePlan(me), pull = makePlan(me)
        let sent = try mark()
        me.reorder([push, pull], fromOffsets: [1], toOffset: 0)
        #expect(try outgoing(after: sent, push, pull).isEmpty)
    }

    @Test func aMoveOutOfASharedPlanIsARemovalThere() throws {
        let shared = makePlan(me, "Bench"), other = makePlan(me)
        let item = shared.sortedItems[0].id
        let sent = try mark()
        me.move(shared.sortedItems[0], to: other)
        #expect(try outgoing(after: sent, shared) == [.deleteExercise(id: item)])
    }

    @Test func aMoveIntoASharedPlanIsAnAdditionThere() throws {
        let other = makePlan(me, "Bench"), shared = makePlan(me)
        let item = other.sortedItems[0].id
        let sent = try mark()
        me.move(other.sortedItems[0], to: shared)
        #expect(try outgoing(after: sent, shared) == [.addExercise(id: item, plan: shared.id, exerciseID: "Bench", order: 0)])
    }

    @Test func yourOwnExerciseIsThePartnersOwnThere() throws {
        let plan = makePlan(me)
        let item = me.add("Curl", to: plan, own: .mine)
        try send(plan)
        #expect(partner.item(item.id)?.ownedBy == .partner)
    }

    @Test func anExerciseYouMadeBringsItsName() throws {
        let plan = makePlan(me, me.createExercise(named: "Cable Fly"))
        try send(plan)
        let id = try #require(partner.plan(plan.id)?.sortedItems.first?.exerciseID)
        #expect(partner.exerciseName(id) == "Cable Fly")
    }

    @Test func aNewExerciseStartsWithTheSendersSetsAndRepsAndYourLastWeight() throws {
        let plan = makePlan(me)
        try send(plan)
        partner.log("Bench", reps: 8, weightKg: 60, in: partner.startWorkout(try #require(partner.plan(plan.id))))
        let sent = try mark()
        me.setTargets(me.add("Bench", to: plan), sets: 4, reps: 8)
        try send(after: sent, plan)
        let item = try #require(partner.plan(plan.id)?.sortedItems.first)
        #expect((item.targetSets, item.targetReps, item.targetWeightKg) == (4, 8, 60))
    }

    @Test func aReplacedExerciseTakesYourLastWeight() throws {
        let plan = makePlan(me, "Bench")
        try send(plan)
        partner.log("Curl", reps: 10, weightKg: 12, in: partner.startWorkout(try #require(partner.plan(plan.id))))
        let sent = try mark()
        me.replace(plan.sortedItems[0], with: "Curl")
        try send(after: sent, plan)
        #expect(partner.plan(plan.id)?.sortedItems.first?.targetWeightKg == 12)
    }

    @Test func aChangeArrivingTwiceAppliesOnce() throws {
        let plan = makePlan(me, "Bench")
        try send(plan)
        try send(plan)
        #expect(try partner.fetchCount(FetchDescriptor<Action>()) == 3) // the plan, the exercise, and its targets there
    }

    @Test func theLaterRenameWins() throws {
        let plan = makePlan(me)
        try send(plan)
        let sent = try mark()
        me.rename(plan, to: "Push")
        partner.rename(try #require(partner.plan(plan.id)), to: "Push day")
        try send(after: sent, plan)
        #expect(partner.plan(plan.id)?.name == "Push day")
    }

    @Test func aReceivedPlanGoesToTheEndOfTheList() throws {
        makePlan(partner)
        makePlan(partner)
        let plan = makePlan(me)
        try send(plan)
        #expect(partner.plan(plan.id)?.order == 2)
    }

    @Test func aChangeFromThePartnerSaysWhoMadeIt() throws {
        try send(makePlan(me))
        #expect(try history(theirs).first?.author == "Me")
    }

    @Test func aChangeToAPlanThatIsNotThereChangesNothing() throws {
        let plan = makePlan(me)
        let sent = try mark()
        me.add("Bench", to: plan)
        try send(after: sent, plan)
        #expect(try partner.fetchCount(FetchDescriptor<PlanItem>()) == 0)
    }

    // "Only me"

    @Test func removingOnlyForYouLeavesItToThePartner() {
        let item = makePlan(me, "Bench").sortedItems[0]
        me.deleteExercise(item, forBoth: false)
        #expect(item.ownedBy == .partner)
    }

    @Test func replacingOnlyForYouPutsYoursRightAfterTheirs() {
        let plan = makePlan(me, "Bench", "Row")
        me.replace(plan.sortedItems[0], with: "Curl", forBoth: false)
        #expect(plan.sortedItems.map { "\($0.exerciseID) \($0.ownedBy)" } == ["Bench partner", "Curl me", "Row both"])
    }

    @Test func movingOnlyForYouLeavesItToThePartnerAndTakesYours() {
        let from = makePlan(me, "Bench"), to = makePlan(me)
        me.move(from.sortedItems[0], to: to, forBoth: false)
        #expect(from.sortedItems.map(\.ownedBy) == [.partner] && to.sortedItems.map(\.ownedBy) == [.me])
    }

    @Test func trainingSkipsThePartnersOwnExercises() {
        let plan = makePlan(me, "Bench", "Row")
        me.deleteExercise(plan.sortedItems[0], forBoth: false)
        #expect(plan.trainedItems.map(\.exerciseID) == ["Row"])
    }

    @Test func exercisesAtTheSamePlaceSortByID() {
        let plan = makePlan(me)
        let ids = [UUID(), UUID()]
        for id in ids { me.record(.addExercise(id: id, plan: plan.id, exerciseID: "Bench", order: 0)) }
        #expect(plan.sortedItems.map(\.id) == ids.sorted { $0.uuidString < $1.uuidString })
    }
}
