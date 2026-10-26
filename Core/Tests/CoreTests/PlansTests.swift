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
        context.add([PlannedExercise(name: "barbell back squat", sets: 3, reps: 10, weightKg: 0), PlannedExercise(name: "cable fly", sets: 3, reps: 10, weightKg: 0)], to: plan)
        #expect(plan.sortedItems.map(\.exerciseID) == ["squat", custom])
    }

    @Test func describedExerciseNotInTheCatalogBecomesYourOwn() {
        let plan = makePlan(context)
        context.add([PlannedExercise(name: "Zercher Carry", sets: 3, reps: 10, weightKg: 0)], to: plan)
        let id = plan.sortedItems[0].exerciseID
        #expect(exerciseName(id, entry: context.catalogEntry(id)) == "Zercher Carry")
    }

    @Test func describedExerciseGetsItsTargets() {
        let plan = makePlan(context)
        context.add([PlannedExercise(name: "Barbell Back Squat", sets: 5, reps: 5, weightKg: 100)], to: plan)
        let item = plan.sortedItems[0]
        #expect((item.targetSets, item.targetReps, item.targetWeightKg) == (5, 5, 100))
    }

    @Test func movedExerciseKeepsItsTargetsAtTheEndOfTheOtherPlan() {
        let item = makePlan(context, "Bench").sortedItems[0]
        context.setTargets(item, sets: 5, reps: 5, weightKg: 80)
        let other = makePlan(context, "Squat")
        context.move(item, to: other)
        #expect(other.sortedItems.map(\.exerciseID) == ["Squat", "Bench"])
        #expect((item.targetSets, item.targetReps, item.targetWeightKg) == (5, 5, 80))
    }

    @Test func replacedExerciseStaysInItsPlace() {
        let plan = makePlan(context, "Bench", "Squat", "Row")
        context.replace(plan.sortedItems[1], with: "Curl")
        #expect(plan.sortedItems.map(\.exerciseID) == ["Bench", "Curl", "Row"])
    }

    @Test func replacedExerciseStartsAtYourLastWeightOfIt() {
        let plan = makePlan(context, "Bench")
        context.log("Curl", reps: 10, weightKg: 12.5, in: context.startWorkout(plan))
        context.replace(plan.sortedItems[0], with: "Curl")
        #expect(plan.sortedItems[0].targetWeightKg == 12.5)
    }

    @Test func replacedExerciseYouNeverDidStartsAtZero() {
        let item = makePlan(context, "Bench").sortedItems[0]
        context.setTargets(item, weightKg: 80)
        context.replace(item, with: "Curl")
        #expect(item.targetWeightKg == 0)
    }

    @Test func settingOneTargetKeepsTheOthers() {
        let item = makePlan(context, "Bench").sortedItems[0]
        context.setTargets(item, sets: 5)
        context.setTargets(item, reps: 6)
        context.setTargets(item, weightKg: 70)
        #expect((item.targetSets, item.targetReps, item.targetWeightKg) == (5, 6, 70))
    }
}
