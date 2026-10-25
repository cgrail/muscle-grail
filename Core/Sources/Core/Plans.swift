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

    /// Appends `exercise` to the end of `plan`.
    @discardableResult
    func add(_ exercise: String, to plan: Plan) -> PlanItem {
        let id = UUID()
        record(.addExercise(id: id, plan: plan.id, exercise: exercise, order: (plan.sortedItems.last?.order ?? -1) + 1))
        return item(id)!
    }

    func rename(_ item: PlanItem, to exercise: String) {
        record(.renameExercise(id: item.id, exercise: exercise))
    }

    /// Changes the targets given and keeps the others.
    func setTargets(_ item: PlanItem, sets: Int? = nil, reps: Int? = nil, weightKg: Double? = nil) {
        record(.setTargets(id: item.id, sets: sets ?? item.targetSets, reps: reps ?? item.targetReps, weightKg: weightKg ?? item.targetWeightKg))
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
