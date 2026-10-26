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

    /// Appends the catalog exercise `exerciseID` to the end of `plan`: for both, or in a shared plan one person's own.
    @discardableResult
    func add(_ exerciseID: String, to plan: Plan, own: Own? = nil) -> PlanItem {
        let id = UUID()
        record(.addExercise(id: id, plan: plan.id, exerciseID: exerciseID, order: (plan.sortedItems.last?.order ?? -1) + 1, own: own))
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

    /// Moves `item` to the end of `plan`, with its sets, reps and weight. Only for you, an exercise for both stays where it was
    /// as the training partner's own, and goes into `plan` as yours.
    func move(_ item: PlanItem, to plan: Plan, forBoth: Bool = true) {
        guard !forBoth, item.ownedBy == .both else {
            return record(.moveExercise(id: item.id, plan: plan.id, order: (plan.sortedItems.last?.order ?? -1) + 1))
        }
        record(.setOwner(id: item.id, own: .theirs))
        setTargets(add(item.exerciseID, to: plan, own: .mine), sets: item.targetSets, reps: item.targetReps, weightKg: item.targetWeightKg)
    }

    /// Swaps `item`'s exercise for `exerciseID` in its place. Sets and reps stay; the weight is your last set's of it, else 0 kg.
    /// Only for you, an exercise for both stays as the training partner's own, and yours goes right after it.
    func replace(_ item: PlanItem, with exerciseID: String, forBoth: Bool = true) {
        let weightKg = lastWeight(of: exerciseID) ?? 0
        guard !forBoth, item.ownedBy == .both, let plan = item.plan else {
            return record(.replaceExercise(id: item.id, exerciseID: exerciseID, weightKg: weightKg))
        }
        record(.setOwner(id: item.id, own: .theirs))
        let yours = add(exerciseID, to: plan, own: .mine)
        setTargets(yours, sets: item.targetSets, reps: item.targetReps, weightKg: weightKg)
        var ids = plan.sortedItems.map(\.id).filter { $0 != yours.id }
        ids.insert(yours.id, at: (ids.firstIndex(of: item.id) ?? ids.count - 1) + 1)
        record(.reorder(ids: ids))
    }

    /// Removes `item`. Only for you, an exercise for both stays in the plan as the training partner's own.
    func deleteExercise(_ item: PlanItem, forBoth: Bool = true) {
        record(!forBoth && item.ownedBy == .both ? .setOwner(id: item.id, own: .theirs) : .deleteExercise(id: item.id))
    }

    /// Your weight in your last set of `exerciseID`, if you ever did it.
    func lastWeight(of exerciseID: String) -> Double? {
        var last = FetchDescriptor<LoggedSet>(predicate: #Predicate { $0.exerciseID == exerciseID }, sortBy: [SortDescriptor(\.date, order: .reverse)])
        last.fetchLimit = 1
        return (try? fetch(last))?.first?.weightKg
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
