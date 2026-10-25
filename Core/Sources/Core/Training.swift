import Foundation
import SwiftData

// Training: works on every app version and never asks for an update (see `Change`).
public extension ModelContext {
    func startWorkout(_ plan: Plan) -> Workout {
        let id = UUID()
        record(.startWorkout(id: id, plan: plan.id, start: .now))
        try? save()
        return workout(id)!
    }

    @discardableResult
    func log(_ exerciseID: String, reps: Int, weightKg: Double, in workout: Workout) -> LoggedSet {
        let id = UUID()
        record(.logSet(id: id, workout: workout.id, exerciseID: exerciseID, reps: reps, weightKg: weightKg, date: .now))
        try? save() // save right away: the watch app can be killed between sets
        return loggedSet(id)!
    }

    /// Ticks off the next set as prefilled (`nextSet`), from the workout list. An exercise with all its sets done stays as it is.
    func tick(_ item: PlanItem, in workout: Workout) {
        guard workout.sets(of: item.exerciseID).count < item.targetSets else { return }
        let (reps, weightKg) = nextSet(for: item, in: workout)
        log(item.exerciseID, reps: reps, weightKg: weightKg, in: workout)
    }

    /// Ticks off an exercise in one go: logs its remaining sets with the same reps and weight.
    func logRemaining(of item: PlanItem, in workout: Workout, reps: Int, weightKg: Double) {
        for _ in 0..<max(0, item.targetSets - workout.sets(of: item.exerciseID).count) {
            log(item.exerciseID, reps: reps, weightKg: weightKg, in: workout)
        }
    }

    /// The undo for `log`: logged sets are never edited, only deleted.
    func undo(_ set: LoggedSet) {
        record(.deleteSet(id: set.id))
        try? save()
    }

    func finish(_ workout: Workout) {
        record(.finishWorkout(id: workout.id, end: .now))
        try? save()
    }

    /// Only the device that ran the workout saves it to Health, then stores its id here.
    func savedToHealth(_ workout: Workout, as healthKitID: UUID) {
        record(.savedToHealth(workout: workout.id, healthKitID: healthKitID))
        try? save()
    }

    func deleteWorkout(_ workout: Workout) {
        record(.deleteWorkout(id: workout.id))
    }

    /// Sets of the most recent earlier workout that included `exerciseID`, in the order they were done.
    func lastSets(of exerciseID: String, excluding current: Workout) -> [LoggedSet] {
        let descriptor = FetchDescriptor<LoggedSet>(
            predicate: #Predicate { $0.exerciseID == exerciseID },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let earlier = ((try? fetch(descriptor)) ?? []).filter { $0.workout != nil && $0.workout != current }
        guard let last = earlier.first?.workout else { return [] }
        return earlier.filter { $0.workout == last }.reversed()
    }

    /// Prefill for the next set: repeat the set just done, else the first set of last time, else the plan.
    func nextSet(for item: PlanItem, in workout: Workout) -> (reps: Int, weightKg: Double) {
        let set = workout.sets(of: item.exerciseID).last ?? lastSets(of: item.exerciseID, excluding: workout).first
        guard let set else { return (item.targetReps, item.targetWeightKg) }
        return (set.reps, set.weightKg)
    }
}
