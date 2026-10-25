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
}
