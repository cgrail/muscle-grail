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
}
