import Foundation
import SwiftData
import Testing
@testable import Core

@MainActor struct PlansTests {
    let container = try! Store.makeContainer(inMemory: true)
    var context: ModelContext { container.mainContext }

    @Test func describedExercisesUseTheirCatalogEntryIgnoringCase() {
        let custom = context.createExercise(named: "Cable Fly")
        let plan = makePlan(context)
        context.add([PlannedExercise(name: "barbell squat", sets: 3, reps: 10, weightKg: 0), PlannedExercise(name: "cable fly", sets: 3, reps: 10, weightKg: 0)], to: plan)
        #expect(plan.sortedItems.map(\.exerciseID) == ["Barbell_Squat", custom])
    }

    @Test func describedExerciseNotInTheCatalogBecomesYourOwn() {
        let plan = makePlan(context)
        context.add([PlannedExercise(name: "Zercher Carry", sets: 3, reps: 10, weightKg: 0)], to: plan)
        let id = plan.sortedItems[0].exerciseID
        #expect(exerciseName(id, entry: context.catalogEntry(id)) == "Zercher Carry")
    }

    @Test func describedExerciseGetsItsTargets() {
        let plan = makePlan(context)
        context.add([PlannedExercise(name: "Barbell Squat", sets: 5, reps: 5, weightKg: 100)], to: plan)
        let item = plan.sortedItems[0]
        #expect((item.targetSets, item.targetReps, item.targetWeightKg) == (5, 5, 100))
    }

    @Test func settingOneTargetKeepsTheOthers() {
        let item = makePlan(context, "Bench").sortedItems[0]
        context.setTargets(item, sets: 5)
        context.setTargets(item, reps: 6)
        context.setTargets(item, weightKg: 70)
        #expect((item.targetSets, item.targetReps, item.targetWeightKg) == (5, 6, 70))
    }
}
