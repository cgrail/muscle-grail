import Foundation
import SwiftData
import Testing
@testable import Core

@MainActor struct ModelsTests {
    let container = try! Store.makeContainer(inMemory: true)
    var context: ModelContext { container.mainContext }

    @Test func unnamedPlanIsTitledUntitled() {
        #expect(Plan(name: "", order: 0).title == "Untitled")
    }

    @Test func workoutWithoutPlanIsTitledWorkout() {
        #expect(Workout().title == "Workout")
    }

    @Test func exercisesGroupSetsInTheOrderTheyWereDone() {
        let workout = context.startWorkout(makePlan(context))
        for (exercise, reps) in [("Bench", 10), ("Squat", 5), ("Bench", 8)] {
            context.log(exercise, reps: reps, weightKg: 50, in: workout)
        }
        #expect(workout.exercises.map(\.id) == ["Bench", "Squat"])
        #expect(workout.exercises.map { $0.sets.map(\.reps) } == [[10, 8], [5]])
    }

    @Test func workoutIsCompleteOnceEveryExerciseHasItsTargetSets() {
        let plan = makePlan(context, "Bench", "Squat")
        let workout = context.startWorkout(plan)
        context.logRemaining(of: plan.sortedItems[0], in: workout, reps: 10, weightKg: 50)
        #expect(!workout.isComplete)
        context.logRemaining(of: plan.sortedItems[1], in: workout, reps: 5, weightKg: 80)
        #expect(workout.isComplete)
    }

    @Test func planFocusIsTheRegionWithMoreThanHalfTheSets() {
        #expect(makePlan(context, "squat", "leg-curl", "barbell-curl").focus == "Leg-heavy")
    }

    @Test func planFocusNamesTheTopTwoRegionsWhenTheyGetTwoThirds() {
        let plan = makePlan(context, "bench-press", "pull-up", "plank")
        context.setTargets(plan.sortedItems[2], sets: 1)
        #expect(plan.focus == "Chest & Back")
    }

    @Test func planFocusIsFullBodyWhenSpread() {
        #expect(makePlan(context, "squat", "bench-press", "pull-up").focus == "Full body")
    }

    @Test func planOfYourOwnExercisesHasNoFocus() {
        #expect(makePlan(context, context.createExercise(named: "Zercher Carry")).focus == nil)
    }
}
