import Foundation
import SwiftData

// The app runs the newest schema version. To change the model, see `MigrationPlan`.
public typealias CurrentSchema = SchemaV1
public typealias Plan = CurrentSchema.Plan
public typealias PlanItem = CurrentSchema.PlanItem
public typealias Workout = CurrentSchema.Workout
public typealias LoggedSet = CurrentSchema.LoggedSet
public typealias Action = CurrentSchema.Action
public typealias CatalogEntry = CurrentSchema.CatalogEntry
public typealias CatalogAction = CurrentSchema.CatalogAction

/// A schema version, split into the two stores the app keeps.
public protocol StoreLayout: VersionedSchema {
    static var gymModels: [any PersistentModel.Type] { get }
    static var catalogModels: [any PersistentModel.Type] { get }
}

public extension StoreLayout {
    static var models: [any PersistentModel.Type] { gymModels + catalogModels }
}

/// Every schema version, oldest first, and how each migrates to the next, so a store from any version opens in the newest.
/// To change the model: copy the newest `SchemaV<n>.swift` to `SchemaV<n+1>.swift` and change only the copy, additively.
/// Point `CurrentSchema` above at it, append it to `schemas` with a `.lightweight` stage from the one before,
/// and give it a seed in `MigrationTests`.
enum MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] } // CloudKit stores only migrate lightweight, which additive changes are
}

public extension Plan {
    var sortedItems: [PlanItem] { (items ?? []).sorted { $0.order < $1.order } }

    var title: String { name.isEmpty ? String(localized: "Untitled", bundle: .module) : name }
}

public extension Workout {
    static var unfinished: FetchDescriptor<Workout> {
        FetchDescriptor(predicate: #Predicate { $0.end == nil }, sortBy: [SortDescriptor(\.start)])
    }

    static var history: FetchDescriptor<Workout> {
        FetchDescriptor(sortBy: [SortDescriptor(\.start, order: .reverse)])
    }

    var title: String { plan?.title ?? String(localized: "Workout", bundle: .module) }

    func sets(of exerciseID: String) -> [LoggedSet] {
        (sets ?? []).filter { $0.exerciseID == exerciseID }.sorted { $0.date < $1.date }
    }

    /// Exercises in the order they were first done, each with its sets in order.
    var exercises: [(id: String, sets: [LoggedSet])] {
        let sorted = (sets ?? []).sorted { $0.date < $1.date }
        let ids = sorted.map(\.exerciseID).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return ids.map { id in (id, sorted.filter { $0.exerciseID == id }) }
    }
}
