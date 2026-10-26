import Foundation
import SwiftData

/// A plan change between training partners, as the shared zone holds it (PLAN.md, Sharing plans with a training partner).
public struct PartnerChange: Codable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var change: Change
    public var batch: UUID?
    /// For a new exercise: the sender's sets and reps, as a start.
    public var sets: Int?
    public var reps: Int?
    /// For an exercise the sender made: its name, so the partner sees it. Its description, video and photo stay with the sender.
    public var name: String?

    public init(id: UUID, date: Date, change: Change, batch: UUID? = nil, sets: Int? = nil, reps: Int? = nil, name: String? = nil) {
        (self.id, self.date, self.change, self.batch, self.sets, self.reps, self.name) = (id, date, change, batch, sets, reps, name)
    }
}

public extension PartnerChange {
    /// What this person changed after `after`, as the training partner gets it, oldest first: every change to a plan in `shared`
    /// but sets, reps and weights, and never the order of the plan list. It comes from the log, so nothing made offline is lost.
    static func outgoing(_ container: ModelContainer, after: Date, shared: Set<UUID>) throws -> [PartnerChange] {
        let context = ModelContext(container)
        var walk = Walk(context: context)
        var changes: [PartnerChange] = []
        for action in try context.fetch(FetchDescriptor<Action>(sortBy: [SortDescriptor(\.date)])) {
            guard let change = action.change else { continue }
            if action.author == nil, action.date > after, let out = walk.outgoing(change, shared: shared) {
                changes.append(PartnerChange(id: action.id, date: action.date, change: out, batch: action.batch, name: context.ownName(of: out)))
            }
            _ = walk.step(change, by: action.author)
        }
        for index in changes.indices {
            guard case let .addExercise(id, _, _, _, _) = changes[index].change, let item = walk.items[id] else { continue }
            (changes[index].sets, changes[index].reps) = (item.sets, item.reps)
        }
        return changes
    }
}

extension Walk {
    /// What the training partner gets for `change`, from the state before it.
    func outgoing(_ change: Change, shared: Set<UUID>) -> Change? {
        func isShared(_ item: UUID) -> Bool { items[item].map { shared.contains($0.plan) } ?? false }
        switch change {
        case let .addPlan(id, _, _), let .renamePlan(id, _), let .deletePlan(id):
            return shared.contains(id) ? change : nil
        case let .addExercise(_, plan, _, _, _):
            return shared.contains(plan) ? change : nil
        case let .replaceExercise(id, _, _), let .deleteExercise(id), let .setOwner(id, _):
            return isShared(id) ? change : nil
        case let .reorder(ids):
            return ids.first.map(isShared) == true ? change : nil
        case let .moveExercise(id, plan, order):
            guard let item = items[id] else { return nil }
            switch (shared.contains(item.plan), shared.contains(plan)) {
            case (true, true): return change
            case (true, false): return .deleteExercise(id: id)
            case (false, true): return .addExercise(id: id, plan: plan, exerciseID: item.exerciseID, order: order, own: item.owner.own)
            case (false, false): return nil
            }
        default:
            return nil
        }
    }
}

public extension ModelContext {
    /// Applies changes from the training partner, oldest first, through `record` with their name and their side's id and date,
    /// so they are in the log, the history and the backup, and never go back. One that's already here, or that lost to
    /// a later rename, reorder or move of the same plan or exercise, is left out: the later one wins on both sides.
    func receive(_ changes: [PartnerChange], from partner: String) {
        for incoming in changes.sorted(by: { $0.date < $1.date }) where !received(incoming.id) && !outdated(incoming) {
            guard let change = adapted(incoming.change) else { continue }
            if let name = incoming.name, let exerciseID = change.exerciseID, catalogEntry(exerciseID) == nil {
                record(.editExercise(id: exerciseID, name: name, details: "", videoURL: ""))
            }
            record(change, batch: incoming.batch, author: partner, id: incoming.id, date: incoming.date)
            if case let .addExercise(id, _, exerciseID, _, _) = change, let item = item(id) {
                record(.setTargets(id: id, sets: incoming.sets ?? item.targetSets, reps: incoming.reps ?? item.targetReps,
                                   weightKg: lastWeight(of: exerciseID) ?? 0), author: partner)
            }
        }
    }

    /// The name of an exercise the user made, for a change that brings one into a plan.
    fileprivate func ownName(of change: Change) -> String? {
        guard let exerciseID = change.exerciseID, CatalogExercise.byID[exerciseID] == nil else { return nil }
        return catalogEntry(exerciseID).map(\.name).flatMap { $0.isEmpty ? nil : $0 }
    }

    private func received(_ id: UUID) -> Bool {
        ((try? fetchCount(FetchDescriptor<Action>(predicate: #Predicate { $0.id == id }))) ?? 0) > 0
    }

    private func outdated(_ incoming: PartnerChange) -> Bool {
        guard let target = target(of: incoming.change) else { return false }
        let since = incoming.date
        let later = (try? fetch(FetchDescriptor<Action>(predicate: #Predicate { $0.date > since }))) ?? []
        return later.contains { action in action.change.flatMap { self.target(of: $0) } == target }
    }

    /// What a rename, reorder or move wins or loses against: its kind, and the plan or exercise it changes.
    private func target(of change: Change) -> String? {
        switch change {
        case let .renamePlan(id, _): "rename \(id)"
        case let .reorder(ids): ids.first.map { "reorder \(item($0)?.plan?.id ?? $0)" }
        case let .moveExercise(id, _, _): "move \(id)"
        default: nil
        }
    }

    /// A received change as it applies here: a new plan at the end of the list, nothing for a plan that isn't here,
    /// and a replaced exercise at this person's own last weight of it.
    private func adapted(_ change: Change) -> Change? {
        switch change {
        case let .addPlan(id, name, _):
            let last = ((try? fetch(FetchDescriptor<Plan>())) ?? []).map(\.order).max() ?? -1
            return .addPlan(id: id, name: name, order: plan(id)?.order ?? last + 1)
        case let .addExercise(_, plan, _, _, _):
            return self.plan(plan) == nil ? nil : change
        case let .replaceExercise(id, exerciseID, _):
            return .replaceExercise(id: id, exerciseID: exerciseID, weightKg: lastWeight(of: exerciseID) ?? 0)
        default:
            return change
        }
    }
}

extension Change {
    /// The exercise a change brings into a plan.
    var exerciseID: String? {
        switch self {
        case let .addExercise(_, _, exerciseID, _, _), let .replaceExercise(_, exerciseID, _): exerciseID
        default: nil
        }
    }
}
