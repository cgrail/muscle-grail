import Foundation
import SwiftData

// A schema version is frozen once a TestFlight or App Store build has shipped it. To change the model, see `MigrationPlan`.
// CloudKit rules: every property has a default or is optional, every relationship is optional
// and has an inverse, no unique constraints, no ordered relationships (hence `order`).

public enum SchemaV1: StoreLayout {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    public static var gymModels: [any PersistentModel.Type] { [Plan.self, PlanItem.self, Workout.self, LoggedSet.self, Action.self] }
    public static var catalogModels: [any PersistentModel.Type] { [CatalogEntry.self, CatalogAction.self] }

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

    @Model public final class PlanItem {
        public var id = UUID()
        /// The catalog id: a bundled exercise's id, or a UUID string for one the user made.
        public var exerciseID = ""
        public var order = 0
        public var targetSets = 3
        public var targetReps = 10
        public var targetWeightKg = 0.0
        /// Whose own it is in a shared plan, an `Owner`: empty for both. Relative to this store's person.
        public var owner = ""
        public var plan: Plan?

        public init(exerciseID: String, order: Int) {
            self.exerciseID = exerciseID
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
        public var exerciseID = ""
        public var reps = 0
        public var weightKg = 0.0
        public var date = Date.now
        public var workout: Workout?

        public init(exerciseID: String, reps: Int, weightKg: Double) {
            self.exerciseID = exerciseID
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
        /// Who made it: nil for this person, else the training partner's name, set when a change from them is recorded.
        public var author: String?
        /// Shared by the changes of one undo or restore, so the history shows them as one entry.
        public var batch: UUID?

        public init() {}
    }

    // The catalog's store: the user's own data for an exercise, and the log of its changes.

    /// The user's own data for a catalog id, on top of the bundled exercise with that id, if there is one.
    @Model public final class CatalogEntry {
        public var id = ""
        /// Empty keeps the bundled name.
        public var name = ""
        public var details = ""
        public var videoURL = ""
        @Attribute(.externalStorage) public var photo: Data?

        public init(id: String) {
            self.id = id
        }
    }

    /// `Action` for the catalog's changes, kept in its store so photos never weigh on the gym data.
    @Model public final class CatalogAction {
        public var id = UUID()
        public var date = Date.now
        public var version = 1
        @Attribute(.externalStorage) public var payload = Data()

        public init() {}
    }
}
