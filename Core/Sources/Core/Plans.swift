import Foundation
import SwiftData
import SwiftUI

/// Plans and their exercises keep their position in `order`, since CloudKit has no ordered relationships.
public protocol Ordered: AnyObject {
    var id: UUID { get }
    var order: Int { get set }
}

extension Plan: Ordered {}
extension PlanItem: Ordered {}

// Plan editing: every function records a `Change`, so nothing edits a model directly.
public extension ModelContext {
    /// A new plan at the end of the list.
    @discardableResult
    func addPlan() -> Plan {
        let last = ((try? fetch(FetchDescriptor<Plan>())) ?? []).map(\.order).max() ?? -1
        let id = UUID()
        record(.addPlan(id: id, name: String(localized: "New plan", bundle: .module), order: last + 1))
        return plan(id)!
    }

    func rename(_ plan: Plan, to name: String) {
        record(.renamePlan(id: plan.id, name: name))
    }

    func deletePlan(_ plan: Plan) {
        record(.deletePlan(id: plan.id))
    }

    /// Appends the catalog exercise `exerciseID` to the end of `plan`.
    @discardableResult
    func add(_ exerciseID: String, to plan: Plan) -> PlanItem {
        let id = UUID()
        record(.addExercise(id: id, plan: plan.id, exerciseID: exerciseID, order: (plan.sortedItems.last?.order ?? -1) + 1))
        return item(id)!
    }

    /// Adds described exercises to `plan`, each by its catalog name or as a new exercise of the user's own.
    func add(_ exercises: [PlannedExercise], to plan: Plan) {
        for exercise in exercises {
            let item = add(catalogID(named: exercise.name) ?? createExercise(named: exercise.name), to: plan)
            setTargets(item, sets: exercise.sets, reps: exercise.reps, weightKg: exercise.weightKg)
        }
    }

    /// Changes the targets given and keeps the others.
    func setTargets(_ item: PlanItem, sets: Int? = nil, reps: Int? = nil, weightKg: Double? = nil) {
        record(.setTargets(id: item.id, sets: sets ?? item.targetSets, reps: reps ?? item.targetReps, weightKg: weightKg ?? item.targetWeightKg))
    }

    /// Moves `item` to the end of `plan`, with its sets, reps and weight.
    func move(_ item: PlanItem, to plan: Plan) {
        record(.moveExercise(id: item.id, plan: plan.id, order: (plan.sortedItems.last?.order ?? -1) + 1))
    }

    func deleteExercise(_ item: PlanItem) {
        record(.deleteExercise(id: item.id))
    }

    /// Applies a `List.onMove` to plans or to the exercises of one plan.
    func reorder(_ rows: [some Ordered], fromOffsets source: IndexSet, toOffset destination: Int) {
        var ids = rows.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        record(.reorder(ids: ids))
    }
}

/// An exercise someone described for a plan, by name, as the plan assistant hands it over.
public struct PlannedExercise: Equatable, Sendable {
    public var name: String
    public var sets: Int
    public var reps: Int
    public var weightKg: Double

    public init(name: String, sets: Int, reps: Int, weightKg: Double) {
        (self.name, self.sets, self.reps, self.weightKg) = (name, sets, reps, weightKg)
    }
}
