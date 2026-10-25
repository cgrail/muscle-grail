import Foundation
import SwiftData

public extension ModelContext {
    func startWorkout(_ plan: Plan) -> Workout {
        let workout = Workout()
        insert(workout)
        workout.plan = plan
        try? save()
        return workout
    }

    @discardableResult
    func log(_ exercise: String, reps: Int, weightKg: Double, in workout: Workout) -> LoggedSet {
        let set = LoggedSet(exercise: exercise, reps: reps, weightKg: weightKg)
        insert(set)
        set.workout = workout
        try? save() // save right away: the watch app can be killed between sets
        return set
    }

    /// Sets of the most recent earlier workout that included `exercise`, in the order they were done.
    func lastSets(of exercise: String, excluding current: Workout) -> [LoggedSet] {
        let descriptor = FetchDescriptor<LoggedSet>(
            predicate: #Predicate { $0.exercise == exercise },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let earlier = ((try? fetch(descriptor)) ?? []).filter { $0.workout != nil && $0.workout != current }
        guard let last = earlier.first?.workout else { return [] }
        return earlier.filter { $0.workout == last }.reversed()
    }
}

/// Prefill for the next set: repeat the set just done, else the first set of last time, else the plan.
public func suggestion(for item: PlanItem, done: [LoggedSet], last: [LoggedSet]) -> (reps: Int, weightKg: Double) {
    guard let set = done.last ?? last.first else { return (item.targetReps, item.targetWeightKg) }
    return (set.reps, set.weightKg)
}
