import Foundation
import SwiftData
import Testing
@testable import Core

/// The 10 most-used use cases, end to end through the store. Keep it at 10: to add one, replace the least important.
@MainActor struct UseCaseTests {
    let container = try! Store.makeContainer(inMemory: true)
    var context: ModelContext { container.mainContext }

    // MARK: Mac: plans

    @Test func buildAPlanOnTheMac() {
        let first = context.addPlan()
        let plan = makePlan(context, "Bench", "Squat", "Row")
        #expect(plan.order == first.order + 1)
        #expect(plan.sortedItems.map(\.exercise) == ["Bench", "Squat", "Row"])
    }

    @Test func reorderExercisesOnTheMac() {
        let plan = makePlan(context, "Bench", "Squat", "Row")
        plan.sortedItems.reorder(fromOffsets: [2], toOffset: 0)
        #expect(plan.sortedItems.map(\.exercise) == ["Row", "Bench", "Squat"])
    }

    @Test func deletingAPlanKeepsItsHistory() throws {
        let plan = makePlan(context, "Bench")
        let workout = context.startWorkout(plan)
        context.log("Bench", reps: 8, weightKg: 60, in: workout)
        context.delete(plan)
        try context.save()
        #expect(try context.fetch(Workout.history) == [workout])
        #expect(workout.sets(of: "Bench").count == 1)
    }

    // MARK: Gym: phone and watch

    @Test func startAWorkoutFromAPlan() throws {
        let plan = makePlan(context, "Bench")
        let workout = context.startWorkout(plan)
        #expect(try context.fetch(Workout.unfinished) == [workout])
        #expect(workout.plan == plan)
    }

    @Test func loggedSetIsSavedRightAway() throws {
        let workout = context.startWorkout(makePlan(context, "Bench"))
        context.log("Bench", reps: 8, weightKg: 60, in: workout)
        let relaunched = ModelContext(container) // sees only saved data, like the watch app after it was killed
        #expect(try relaunched.fetch(FetchDescriptor<LoggedSet>()).map(\.reps) == [8])
    }

    @Test func deleteAMistakenSet() {
        let workout = context.startWorkout(makePlan(context, "Bench"))
        let mistake = context.log("Bench", reps: 80, weightKg: 60, in: workout)
        context.log("Bench", reps: 8, weightKg: 60, in: workout)
        context.undo(mistake)
        #expect(workout.sets(of: "Bench").map(\.reps) == [8])
    }

    @Test func firstWorkoutPrefillsFromThePlan() {
        let plan = makePlan(context, "Bench")
        let item = plan.sortedItems[0]
        item.targetReps = 8
        item.targetWeightKg = 40
        #expect(context.nextSet(for: item, in: context.startWorkout(plan)) == (8, 40))
    }

    @Test func nextSetRepeatsTheSetJustDone() {
        let plan = makePlan(context, "Bench")
        let workout = context.startWorkout(plan)
        context.log("Bench", reps: 6, weightKg: 62.5, in: workout)
        #expect(context.nextSet(for: plan.sortedItems[0], in: workout) == (6, 62.5))
    }

    @Test func nextWorkoutPrefillsFromLastTime() {
        let plan = makePlan(context, "Bench")
        let last = context.startWorkout(plan)
        context.log("Bench", reps: 10, weightKg: 60, in: last)
        context.log("Bench", reps: 7, weightKg: 60, in: last)
        context.finish(last)
        #expect(context.nextSet(for: plan.sortedItems[0], in: context.startWorkout(plan)) == (10, 60))
    }

    @Test func finishedWorkoutMovesToHistory() throws {
        let plan = makePlan(context, "Bench")
        let older = context.startWorkout(plan)
        context.finish(older)
        let workout = context.startWorkout(plan)
        context.finish(workout)
        #expect(try context.fetch(Workout.unfinished).isEmpty)
        #expect(try context.fetch(Workout.history) == [workout, older])
    }
}
