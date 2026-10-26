import Foundation
import SwiftData
import Testing
@testable import Core

@MainActor struct PlanHistoryTests {
    let container = try! Store.makeContainer(inMemory: true)
    var context: ModelContext { container.mainContext }

    @Test func historyListsPlanChangesNewestFirst() throws {
        let fly = context.createExercise(named: "Cable Fly")
        let plan = makePlan(context, fly)
        context.deleteExercise(plan.sortedItems[0])
        #expect(try history(container).map(\.text) == [
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
        #expect(try history(container).count == 12)
    }

    @Test func editsInARowAreOneEntry() throws {
        let item = makePlan(context, "Bench").sortedItems[0]
        for kg in [60.0, 62.5, 65] { context.setTargets(item, weightKg: kg) }
        #expect(try history(container).count == 3)
    }

    @Test func historyOfAPlanLeavesOutTheOthers() throws {
        let plan = makePlan(context, "Bench")
        makePlan(context, "Squat")
        #expect(try history(container, of: plan).count == 2)
    }

    @Test func aMoveIsInTheHistoryOfBothPlans() throws {
        let from = makePlan(context, "Bench"), to = makePlan(context)
        context.move(from.sortedItems[0], to: to)
        let move = try #require(history(container).first)
        #expect(try history(container, of: from).first == move && history(container, of: to).first == move)
    }

    @Test func anEntryNamesThePlanAsItWasCalledThen() throws {
        let plan = makePlan(context)
        context.rename(plan, to: "Push")
        #expect(try history(container).first?.planName == String(localized: "New plan", bundle: .module))
    }
}
