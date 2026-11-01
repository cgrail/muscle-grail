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

    @Test func oneTapTicksOffTheRemainingSets() {
        let plan = makePlan(context, "Curl")
        let workout = context.startWorkout(plan)
        context.log("Curl", reps: 10, weightKg: 20, in: workout)
        context.logRemaining(of: plan.sortedItems[0], in: workout, reps: 8, weightKg: 22)
        #expect(workout.sets(of: "Curl").map(\.reps) == [10, 8, 8])
    }

    /// Plans A, B and C, with a workout of `done` (one set each), in that order.
    func rotation(done: [Int]) -> [Plan] {
        let plans = ["A", "B", "C"].map { name in
            let plan = makePlan(context, "Bench")
            context.rename(plan, to: name)
            return plan
        }
        for index in done { context.log("Bench", reps: 5, weightKg: 50, in: context.startWorkout(plans[index])) }
        return plans
    }

    @Test func thePlanDoneLongestAgoComesFirstAndTheOneDoneLastLast() {
        #expect(trainingOrder(rotation(done: [2, 0, 1])).map(\.name) == ["C", "A", "B"])
    }

    @Test func plansNeverDoneComeFirstInPlanOrder() {
        #expect(trainingOrder(rotation(done: [0])).map(\.name) == ["B", "C", "A"])
    }

    @Test func daysAgoCountsCalendarDaysNotHours() {
        let morning = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now)!
        #expect(daysAgo(morning.addingTimeInterval(-3600), from: morning) == "today")
        #expect(daysAgo(morning.addingTimeInterval(-10 * 3600), from: morning) == "yesterday") // 10 pm
        #expect(daysAgo(morning.addingTimeInterval(-14 * 86400), from: morning) == "2 weeks ago")
    }

    @Test func aWorkoutWithoutSetsIsNotDone() {
        let plan = makePlan(context, "Bench")
        _ = context.startWorkout(plan)
        #expect(plan.lastDone == nil)
    }

    @Test func tickLogsTheNextSetAsPrefilled() {
        let plan = makePlan(context, "Row")
        let item = plan.sortedItems[0]
        context.setTargets(item, reps: 10, weightKg: 38)
        let workout = context.startWorkout(plan)
        context.tick(item, in: workout)
        #expect(workout.sets(of: "Row").map { "\($0.reps)×\($0.weightKg)" } == ["10×38.0"])
    }

    @Test func tickingAFinishedExerciseLogsNothingMore() {
        let plan = makePlan(context, "Row")
        let item = plan.sortedItems[0]
        context.setTargets(item, sets: 1)
        let workout = context.startWorkout(plan)
        context.tick(item, in: workout)
        context.tick(item, in: workout)
        #expect(workout.sets(of: "Row").count == 1)
    }

    @Test func aRunningWorkoutBlocksTheNextUntilFinished() {
        let workout = context.startWorkout(makePlan(context, "Bench"))
        #expect(context.isTraining)
        context.finish(workout)
        #expect(!context.isTraining)
    }
}
