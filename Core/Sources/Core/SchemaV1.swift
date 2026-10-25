import Foundation
import SwiftData

// A schema version is frozen once a TestFlight or App Store build has shipped it. To change the model, see `MigrationPlan`.
// CloudKit rules: every property has a default or is optional, every relationship is optional
// and has an inverse, no unique constraints, no ordered relationships (hence `order`).

public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    public static var models: [any PersistentModel.Type] { [Plan.self, PlanItem.self, Workout.self, LoggedSet.self, Action.self] }

    @Model public final class Plan {
        /// Stable across devices: actions refer to it.
        public var id = UUID()
        public var name = ""
        public var order = 0
        @Relationship(deleteRule: .cascade, inverse: \PlanItem.plan) public var items: [PlanItem]? = []
        @Relationship(deleteRule: .nullify, inverse: \Workout.plan) public var workouts: [Workout]? = []

        public init(name: String, order: Int) {
            self.name = name
            self.order = order
        }
    }

    /// Exercises are plain names: offline devices can't create duplicate exercise records,
    /// and renaming an exercise starts a fresh history.
    @Model public final class PlanItem {
        public var id = UUID()
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
        public var id = UUID()
        public var start = Date.now
        public var end: Date?
        /// Set only by the device that saved the workout to HealthKit, so it is never saved twice.
        public var healthKitID: UUID?
        public var plan: Plan?
        @Relationship(deleteRule: .cascade, inverse: \LoggedSet.workout) public var sets: [LoggedSet]? = []

        public init() {}
    }

    /// One record per set and never edited, so two devices can't conflict over it.
    @Model public final class LoggedSet {
        public var id = UUID()
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

    /// One recorded change to the model: `payload` is a `Change` as JSON. The log only grows, so devices can't conflict over it.
    @Model public final class Action {
        public var id = UUID()
        public var date = Date.now
        /// The `Change.version` of the app that recorded it.
        public var version = 1
        public var payload = Data()

        public init() {}
    }
}
