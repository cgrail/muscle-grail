import Foundation
import SwiftData
import Testing
@testable import Core

@MainActor struct RestoreTests {
    let container = try! Store.makeContainer(inMemory: true)
    var context: ModelContext { container.mainContext }

    /// Restores `plan` to how it was after the entry `back` entries before the newest of its history.
    func restore(_ plan: Plan, back: Int) throws {
        context.restore(try history(container, of: plan)[back])
    }

    @Test func restoringBringsBackThePlanAsItWasAfterAnEntry() throws {
        let plan = makePlan(context, "Bench", "Row")
        context.setTargets(plan.sortedItems[0], weightKg: 80)
        context.rename(plan, to: "Push")
        context.add("Squat", to: plan)
        context.move(plan.sortedItems[1], to: makePlan(context))
        context.setTargets(plan.sortedItems[0], weightKg: 100)
        context.deleteExercise(plan.sortedItems[0])
        // Removed Bench, set Bench to 100, moved Row, added Squat, renamed, set Bench to 80, …
        try restore(plan, back: 5)
        #expect(plan.name == String(localized: "New plan", bundle: .module))
        #expect(plan.sortedItems.map(\.exerciseID) == ["Bench", "Row"])
        #expect(plan.sortedItems[0].targetWeightKg == 80)
    }

    @Test func thePlanAsItIsNowHasNothingToRestore() throws {
        let plan = makePlan(context, "Bench")
        #expect(try history(container, of: plan).map(\.canRestore) == [false, true])
    }

    @Test func aRestoreIsOneEntry() throws {
        let plan = makePlan(context, "Bench", "Row")
        try restore(plan, back: 2) // as just created: removes both exercises
        #expect(try history(container, of: plan).count == 4)
    }

    @Test func aRestoreCanBeUndone() throws {
        let plan = makePlan(context, "Bench", "Row")
        try restore(plan, back: 2)
        context.undo(try #require(history(container, of: plan).first))
        #expect(plan.sortedItems.map(\.exerciseID) == ["Bench", "Row"])
    }
}
