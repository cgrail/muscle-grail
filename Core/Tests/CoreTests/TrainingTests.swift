import Foundation
import SwiftData
import Testing
@testable import Core

@MainActor struct TrainingTests {
    let container = try! Store.makeContainer(inMemory: true)
    var context: ModelContext { container.mainContext }

    @Test func lastSetsComeFromTheMostRecentEarlierWorkoutInOrder() {
        let plan = Plan(name: "A", order: 0)
        context.insert(plan)
        let old = context.startWorkout(plan), recent = context.startWorkout(plan), current = context.startWorkout(plan)
        let logs: [(Workout, String, Int, Double)] = [
            (old, "Bench", 10, 50), (recent, "Bench", 10, 60), (recent, "Squat", 5, 80),
            (recent, "Bench", 9, 60), (current, "Bench", 5, 65),
        ]
        for (minute, (workout, exercise, reps, kg)) in logs.enumerated() {
            context.log(exercise, reps: reps, weightKg: kg, in: workout).date = Date(timeIntervalSince1970: Double(minute) * 60)
        }

        let last = context.lastSets(of: "Bench", excluding: current)
        #expect(last.map(\.reps) == [10, 9])
        #expect(last.allSatisfy { $0.weightKg == 60 })
        #expect(context.lastSets(of: "Deadlift", excluding: current).isEmpty)
    }

    @Test func suggestionPrefersThisWorkoutThenLastTimeThenThePlan() {
        let item = PlanItem(exercise: "Bench", order: 0)
        item.targetReps = 8
        item.targetWeightKg = 40
        let lastTime = [LoggedSet(exercise: "Bench", reps: 10, weightKg: 60), LoggedSet(exercise: "Bench", reps: 7, weightKg: 60)]
        let justDone = [LoggedSet(exercise: "Bench", reps: 6, weightKg: 62.5)]

        #expect(suggestion(for: item, done: [], last: []) == (8, 40))
        #expect(suggestion(for: item, done: [], last: lastTime) == (10, 60))
        #expect(suggestion(for: item, done: justDone, last: lastTime) == (6, 62.5))
    }
}
