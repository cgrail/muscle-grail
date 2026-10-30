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

/// Whose own an exercise of a shared plan is, in this person's store.
public enum Owner: String, Sendable {
    case both = "", me, partner

    /// `own` as this store's person reads it: `author` is nil for their own changes, else the training partner's name.
    init(_ own: Own?, by author: String?) {
        switch (own, author == nil) {
        case (nil, _): self = .both
        case (.mine?, true), (.theirs?, false): self = .me
        case (.mine?, false), (.theirs?, true): self = .partner
        }
    }

    /// As this store's person says it in a change of their own.
    var own: Own? {
        switch self {
        case .both: nil
        case .me: .mine
        case .partner: .theirs
        }
    }
}

public extension PlanItem {
    var ownedBy: Owner { Owner(rawValue: owner) ?? .both }
}

public extension Plan {
    /// In plan order. Two exercises added at the same place, offline on two devices, sort by id, so every device shows the same order.
    var sortedItems: [PlanItem] { (items ?? []).sorted { ($0.order, $0.id.uuidString) < ($1.order, $1.id.uuidString) } }

    /// The exercises this person trains: all but the training partner's own.
    var trainedItems: [PlanItem] { sortedItems.filter { $0.ownedBy != .partner } }

    var title: String { name.isEmpty ? String(localized: "Untitled", bundle: .module) : name }

    /// When this plan was last trained. A workout without sets doesn't count.
    var lastDone: Date? { workouts?.filter { $0.sets?.isEmpty == false }.map(\.start).max() }

    /// What the plan trains, by its target sets per body region: "Leg-heavy" when one region gets more than half,
    /// else its top two while they get more than two thirds, else "Full body". Nil while it has no bundled exercise.
    var focus: String? {
        var sets = [BodyRegion: Int]()
        for item in trainedItems {
            for region in CatalogExercise.byID[item.exerciseID]?.regions ?? [] { sets[region, default: 0] += item.targetSets }
        }
        let ranked = BodyRegion.allCases.filter { sets[$0, default: 0] > 0 }.sorted { sets[$0]! > sets[$1]! }
        let total = sets.values.reduce(0, +)
        guard let top = ranked.first else { return nil }
        if sets[top]! * 2 > total { return top.heavy }
        let second = ranked[1] // top has at most half, so another region has sets
        if (sets[top]! + sets[second]!) * 3 > total * 2 { return String(localized: "\(top.name) & \(second.name)", bundle: .module) }
        return String(localized: "Full body", bundle: .module)
    }
}

/// The plan to do next: the one after the plan trained most recently, in plan order and round again. Else the first.
public func nextPlan(_ plans: [Plan]) -> Plan? {
    let sorted = plans.sorted { $0.order < $1.order }
    guard let last = sorted.filter({ $0.lastDone != nil }).max(by: { $0.lastDone! < $1.lastDone! }),
          let index = sorted.firstIndex(of: last) else { return sorted.first }
    return sorted[(index + 1) % sorted.count]
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

    /// Reps times weight, over every set.
    var volumeKg: Double { (sets ?? []).map { Double($0.reps) * $0.weightKg }.reduce(0, +) }

    /// Whether every exercise this person trains in the plan has its target sets.
    var isComplete: Bool { plan?.trainedItems.allSatisfy { sets(of: $0.exerciseID).count >= $0.targetSets } ?? false }

    /// Exercises in the order they were first done, each with its sets in order.
    var exercises: [(id: String, sets: [LoggedSet])] {
        let sorted = (sets ?? []).sorted { $0.date < $1.date }
        let ids = sorted.map(\.exerciseID).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return ids.map { id in (id, sorted.filter { $0.exerciseID == id }) }
    }
}
