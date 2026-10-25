import Foundation
import SwiftData

// CloudKit rules: every property has a default or is optional, every relationship is optional
// and has an inverse, no unique constraints, no ordered relationships (hence `order`).

@Model public final class Plan {
    public var name = ""
    public var order = 0
    @Relationship(deleteRule: .cascade, inverse: \PlanItem.plan) public var items: [PlanItem]? = []
    @Relationship(deleteRule: .nullify, inverse: \Workout.plan) public var workouts: [Workout]? = []

    public init(name: String, order: Int) {
        self.name = name
        self.order = order
    }

    public var sortedItems: [PlanItem] { (items ?? []).sorted { $0.order < $1.order } }

    public var title: String { name.isEmpty ? String(localized: "Untitled", bundle: .module) : name }
}

/// Exercises are plain names: offline devices can't create duplicate exercise records,
/// and renaming an exercise starts a fresh history.
@Model public final class PlanItem {
    public var exercise = ""
    public var order = 0
    public var targetSets = 3
    public var targetReps = 10
    public var targetWeightKg = 0.0
    public var plan: Plan?

    public init(exercise: String, order: Int) {
        self.exercise = exercise
        self.order = order
    }
}

@Model public final class Workout {
    public var start = Date.now
    public var end: Date?
    /// Set only by the device that saved the workout to HealthKit, so it is never saved twice.
    public var healthKitID: UUID?
    public var plan: Plan?
    @Relationship(deleteRule: .cascade, inverse: \LoggedSet.workout) public var sets: [LoggedSet]? = []

    public init() {}

    public static var unfinished: FetchDescriptor<Workout> {
        FetchDescriptor(predicate: #Predicate { $0.end == nil }, sortBy: [SortDescriptor(\.start)])
    }

    public static var history: FetchDescriptor<Workout> {
        FetchDescriptor(sortBy: [SortDescriptor(\.start, order: .reverse)])
    }

    public var title: String { plan?.title ?? String(localized: "Workout", bundle: .module) }

    public func sets(of exercise: String) -> [LoggedSet] {
        (sets ?? []).filter { $0.exercise == exercise }.sorted { $0.date < $1.date }
    }

    /// Exercises in the order they were first done, each with its sets in order.
    public var exercises: [(name: String, sets: [LoggedSet])] {
        let sorted = (sets ?? []).sorted { $0.date < $1.date }
        let names = sorted.map(\.exercise).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return names.map { name in (name, sorted.filter { $0.exercise == name }) }
    }
}

/// One record per set and never edited, so two devices can't conflict over it.
@Model public final class LoggedSet {
    public var exercise = ""
    public var reps = 0
    public var weightKg = 0.0
    public var date = Date.now
    public var workout: Workout?

    public init(exercise: String, reps: Int, weightKg: Double) {
        self.exercise = exercise
        self.reps = reps
        self.weightKg = weightKg
    }
}
