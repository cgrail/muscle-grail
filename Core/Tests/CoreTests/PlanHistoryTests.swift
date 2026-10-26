import Foundation
import SwiftData
import Testing
@testable import Core

@MainActor struct PlanHistoryTests {
    let container = try! Store.makeContainer(inMemory: true)
    var context: ModelContext { container.mainContext }

    /// The history reads the saved log in a context of its own, as the apps do.
    func history(of plan: Plan? = nil) throws -> [PlanChange] {
        try context.save()
        return try PlanChange.history(container, plan: plan?.id)
    }

    @Test func historyListsPlanChangesNewestFirst() throws {
        let fly = context.createExercise(named: "Cable Fly")
        let plan = makePlan(context, fly)
        context.deleteExercise(plan.sortedItems[0])
        #expect(try history().map(\.text) == [
            String(localized: "Removed \("Cable Fly")", bundle: .module),
            String(localized: "Added \("Cable Fly")", bundle: .module),
            String(localized: "Created the plan", bundle: .module),
        ])
    }

    @Test func everyKindOfPlanChangeIsAnEntry() throws {
        let plan = makePlan(context, "Bench", "Row")
        let other = makePlan(context)
        context.rename(plan, to: "Push")
        context.setTargets(plan.sortedItems[0], sets: 5)
        context.reorder(plan.sortedItems, fromOffsets: [1], toOffset: 0)
        context.reorder([plan, other], fromOffsets: [1], toOffset: 0)
        context.replace(plan.sortedItems[0], with: "Curl")
        context.move(plan.sortedItems[1], to: other)
        context.deleteExercise(plan.sortedItems[0])
        context.deletePlan(other)
        #expect(try history().count == 12)
    }

    @Test func editsInARowAreOneEntry() throws {
        let item = makePlan(context, "Bench").sortedItems[0]
        for kg in [60.0, 62.5, 65] { context.setTargets(item, weightKg: kg) }
        #expect(try history().count == 3)
    }

    @Test func historyOfAPlanLeavesOutTheOthers() throws {
        let plan = makePlan(context, "Bench")
        makePlan(context, "Squat")
        #expect(try history(of: plan).count == 2)
    }

    @Test func aMoveIsInTheHistoryOfBothPlans() throws {
        let from = makePlan(context, "Bench"), to = makePlan(context)
        context.move(from.sortedItems[0], to: to)
        let move = try #require(history().first)
        #expect(try history(of: from).first == move && history(of: to).first == move)
    }

    @Test func anEntryNamesThePlanAsItWasCalledThen() throws {
        let plan = makePlan(context)
        context.rename(plan, to: "Push")
        #expect(try history().first?.planName == String(localized: "New plan", bundle: .module))
    }
}
