import Foundation
import SwiftData

// The iPhone and the watch hand each other their training changes over Bluetooth, before iCloud carries them, and a
// watch without plans gets what it needs to train from the iPhone (PLAN.md, How a device stays current).
// `WatchLinkSession` is the thin wrapper that sends and receives them.

/// A training change as the iPhone and the watch hand it to each other, with the id and date of the action that recorded it.
public struct LinkedChange: Codable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var change: Change
}

/// A record the link made here before iCloud brought the other device's own: a copy with the same `id`. Once the
/// original arrives, the copy goes (`dropCopies`), so every device ends with the original alone.
public struct LinkCopy: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case action, workout, set, plan
    }

    var kind: Kind
    var id: UUID
    /// Its `persistentModelID`, as `SyncMonitor.key` writes it: the copy and the original share `id`.
    var key: String
}

extension LinkCopy {
    /// The copy `model` is, if the link makes that kind of record.
    init?(_ model: any PersistentModel) {
        let key = SyncMonitor.key(model.persistentModelID)
        switch model {
        case let action as Action: self.init(kind: .action, id: action.id, key: key)
        case let workout as Workout: self.init(kind: .workout, id: workout.id, key: key)
        case let set as LoggedSet: self.init(kind: .set, id: set.id, key: key)
        case let plan as Plan: self.init(kind: .plan, id: plan.id, key: key) // its exercises go with it
        default: return nil
        }
    }
}

extension Change {
    /// A workout's changes and its sets': what the iPhone and the watch hand each other. Plans stay with iCloud.
    var isTraining: Bool {
        switch self {
        case .startWorkout, .logSet, .deleteSet, .finishWorkout, .savedToHealth, .deleteWorkout: true
        default: false
        }
    }
}

public extension ModelContext {
    /// The training changes recorded here after `after`, oldest first, for the other device. `skipping` are the actions
    /// the link brought here: they go back to no one.
    func linkOutgoing(after: Date, skipping: Set<UUID> = []) throws -> [LinkedChange] {
        try fetch(FetchDescriptor<Action>(predicate: #Predicate { $0.date > after }, sortBy: [SortDescriptor(\.date)])).compactMap { action in
            guard !skipping.contains(action.id), let change = action.change, change.isTraining else { return nil }
            return LinkedChange(id: action.id, date: action.date, change: change)
        }
    }

    /// Applies the other device's training changes, oldest first, through `record` with their id and date, and saves.
    /// One that's here already, through iCloud or the link, is left out. Returns the copies this made.
    func receiveLinked(_ changes: [LinkedChange]) throws -> [LinkCopy] {
        try copies {
            for incoming in changes.sorted(by: { $0.date < $1.date }) where !hasAction(incoming.id) {
                record(incoming.change, id: incoming.id, date: incoming.date)
            }
        }
    }

    /// What a watch needs to train before iCloud brought it anything, as the changes that build it: the plans with their
    /// exercises, each plan's last workout, so the plan due next is on top, and each exercise's, so its weight prefills.
    func linkedStart() throws -> [Change] {
        var changes: [Change] = []
        var workouts: Set<Workout> = []
        for plan in try fetch(FetchDescriptor<Plan>(sortBy: [SortDescriptor(\.order)])) {
            changes += [.addPlan(id: plan.id, name: plan.name, order: plan.order), .setPicture(id: plan.id, picture: plan.picture)]
            for item in plan.sortedItems {
                changes.append(.addExercise(id: item.id, plan: plan.id, exerciseID: item.exerciseID, order: item.order, own: item.ownedBy.own))
                changes.append(.setTargets(id: item.id, sets: item.targetSets, reps: item.targetReps, weightKg: item.targetWeightKg))
                if let workout = lastSet(of: item.exerciseID)?.workout { workouts.insert(workout) }
            }
            if let workout = plan.lastWorkout { workouts.insert(workout) }
        }
        for workout in workouts {
            // One whose plan is gone starts with its first set, as `apply` has it.
            if let plan = workout.plan { changes.append(.startWorkout(id: workout.id, plan: plan.id, start: workout.start)) }
            changes += (workout.sets ?? []).map {
                .logSet(id: $0.id, workout: workout.id, exerciseID: $0.exerciseID, reps: $0.reps, weightKg: $0.weightKg, date: $0.date)
            }
            if let end = workout.end { changes.append(.finishWorkout(id: workout.id, end: end)) }
        }
        return changes
    }

    /// Builds what the iPhone handed a watch without plans (`linkedStart`), and saves. A store that has a plan keeps to
    /// iCloud, which is bringing the others. It records nothing: iCloud brings the log. Returns the copies this made.
    func receiveStart(_ changes: [Change]) throws -> [LinkCopy] {
        guard try fetchCount(FetchDescriptor<Plan>()) == 0 else { return [] }
        return try copies { for change in changes { apply(change) } }
    }

    /// Drops each copy whose original iCloud brought, and saves. A workout's sets, and the end and Health id only its copy
    /// has, go to the original first, as do a plan's workouts. It records nothing: the log holds each change once, and so
    /// does the model again. A plan's copy stays while iCloud may have brought the plan without all its exercises:
    /// `imported` are the stores whose import finished, nil for any.
    /// Returns the copies still waiting. One that's gone, deleted here or by a change from elsewhere, waits no more.
    func dropCopies(_ copies: [LinkCopy], plansOf imported: Set<String>? = nil) throws -> [LinkCopy] {
        // Plans, then workouts, so a plan's workouts and a workout's sets move to the original before their own copies go.
        let ordered = [LinkCopy.Kind.plan, .workout, .set, .action].flatMap { kind in copies.filter { $0.kind == kind } }
        let waiting = try ordered.filter { copy in
            let id = copy.id
            switch copy.kind {
            case .workout:
                return try waits(copy, among: fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id }))) { mine, original in
                    for set in mine.sets ?? [] { set.workout = original }
                    original.end = original.end ?? mine.end
                    original.healthKitID = original.healthKitID ?? mine.healthKitID
                    original.plan = original.plan ?? mine.plan
                }
            case .set:
                return try waits(copy, among: fetch(FetchDescriptor<LoggedSet>(predicate: #Predicate { $0.id == id })))
            case .action:
                return try waits(copy, among: fetch(FetchDescriptor<Action>(predicate: #Predicate { $0.id == id })))
            case .plan:
                let twins = try fetch(FetchDescriptor<Plan>(predicate: #Predicate { $0.id == id }))
                if let imported, let plan = twins.first, !imported.contains(plan.persistentModelID.storeIdentifier ?? "") { return true }
                return waits(copy, among: twins) { mine, original in
                    for workout in mine.workouts ?? [] { workout.plan = original }
                }
            }
        }
        if hasChanges { try save() }
        return waiting
    }

    /// Saves what `changes` inserts and returns it as copies: their identifiers are final once saved.
    private func copies(madeBy changes: () -> Void) throws -> [LinkCopy] {
        let before = Set(insertedModelsArray.map { ObjectIdentifier($0) })
        changes()
        let made = insertedModelsArray.filter { !before.contains(ObjectIdentifier($0)) }
        guard !made.isEmpty else { return [] }
        try save()
        return made.compactMap { LinkCopy($0) }
    }

    private func hasAction(_ id: UUID) -> Bool {
        ((try? fetchCount(FetchDescriptor<Action>(predicate: #Predicate { $0.id == id }))) ?? 0) > 0
    }

    /// Whether `copy` still waits for its original among `twins`, the records with its `id`. Once that's there,
    /// `merge` hands the original what only the copy has, and the copy goes.
    private func waits<T: PersistentModel>(_ copy: LinkCopy, among twins: [T], merge: (_ copy: T, _ original: T) -> Void = { _, _ in }) -> Bool {
        guard let mine = twins.first(where: { SyncMonitor.key($0.persistentModelID) == copy.key }) else { return false }
        guard let original = twins.first(where: { $0 !== mine }) else { return true }
        merge(mine, original)
        delete(mine)
        return false
    }
}
