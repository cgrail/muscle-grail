import Foundation
import SwiftData
import Testing
@testable import Core

@MainActor struct UndoTests {
    let container = try! Store.makeContainer(inMemory: true)
    var context: ModelContext { container.mainContext }

    /// Undoes the newest entry of the history, then saves, as the history view does.
    func undoLast() throws {
        context.undo(try #require(history(container).first))
        try context.save()
    }

    @Test func undoingAnAddedExerciseRemovesIt() throws {
        let plan = makePlan(context, "Bench")
        try undoLast()
        #expect(plan.sortedItems.isEmpty)
    }

    @Test func undoingARemovedExerciseBringsItBackWithItsIDAndTargets() throws {
        let plan = makePlan(context, "Bench")
        let item = plan.sortedItems[0], id = plan.sortedItems[0].id
        context.setTargets(item, sets: 5, reps: 5, weightKg: 80)
        context.deleteExercise(item)
        try undoLast()
        let back = try #require(plan.sortedItems.first)
        #expect((back.id, back.targetSets, back.targetReps, back.targetWeightKg) == (id, 5, 5, 80))
    }

    @Test func undoingTargetEditsBringsBackTheOnesBefore() throws {
        let item = makePlan(context, "Bench").sortedItems[0]
        for kg in [60.0, 62.5, 65] { context.setTargets(item, weightKg: kg) }
        try undoLast()
        #expect(item.targetWeightKg == 0)
    }

    @Test func undoingAMoveTakesTheExerciseBack() throws {
        let from = makePlan(context, "Bench", "Row"), to = makePlan(context)
        context.move(from.sortedItems[0], to: to)
        try undoLast()
        #expect(from.sortedItems.map(\.exerciseID) == ["Bench", "Row"])
    }

    @Test func undoingAReorderBringsBackTheOrderBefore() throws {
        let plan = makePlan(context, "Bench", "Row", "Squat")
        context.reorder(plan.sortedItems, fromOffsets: [2], toOffset: 0)
        try undoLast()
        #expect(plan.sortedItems.map(\.exerciseID) == ["Bench", "Row", "Squat"])
    }

    @Test func undoingARenameBringsBackTheNameBefore() throws {
        let plan = makePlan(context)
        for name in ["P", "Pu", "Push"] { context.rename(plan, to: name) }
        try undoLast()
        #expect(plan.name == String(localized: "New plan", bundle: .module))
    }

    @Test func undoingAReplaceBringsBackTheExerciseAndItsWeight() throws {
        let item = makePlan(context, "Bench").sortedItems[0]
        context.setTargets(item, weightKg: 80)
        context.replace(item, with: "Curl")
        try undoLast()
        #expect((item.exerciseID, item.targetWeightKg) == ("Bench", 80))
    }

    @Test func undoingANewPlanDeletesIt() throws {
        makePlan(context)
        try undoLast()
        #expect(try context.fetchCount(FetchDescriptor<Plan>()) == 0)
    }

    @Test func undoingADeletedPlanBringsItBackWithItsExercises() throws {
        context.deletePlan(makePlan(context, "Bench", "Row"))
        try undoLast()
        let plan = try #require(context.fetch(FetchDescriptor<Plan>()).first)
        #expect(plan.sortedItems.map(\.exerciseID) == ["Bench", "Row"])
    }

    @Test func undoIsOffOnceWhatItChangedIsGone() throws {
        let plan = makePlan(context, "Bench")
        context.deleteExercise(plan.sortedItems[0])
        // Removed Bench, Added Bench (gone since), Created the plan
        #expect(try history(container).map(\.canUndo) == [true, false, true])
    }

    @Test func anUndoIsOneEntry() throws {
        let item = makePlan(context, "Bench").sortedItems[0]
        context.setTargets(item, weightKg: 80)
        context.deleteExercise(item)
        try undoLast() // adds Bench back and sets its targets: two changes
        #expect(try history(container).count == 5)
    }

    @Test func anUndoCanBeUndone() throws {
        let plan = makePlan(context, "Bench")
        context.deleteExercise(plan.sortedItems[0])
        try undoLast()
        try undoLast()
        #expect(plan.sortedItems.isEmpty)
    }
}
