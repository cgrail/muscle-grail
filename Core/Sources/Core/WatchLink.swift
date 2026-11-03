import Foundation
import SwiftData

// The iPhone and the watch hand each other their training changes over Bluetooth, before iCloud carries them
// (PLAN.md, How a device stays current). `WatchLinkSession` is the thin wrapper that sends and receives them.

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
        case action, workout, set
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
        let before = Set(insertedModelsArray.map { ObjectIdentifier($0) })
        for incoming in changes.sorted(by: { $0.date < $1.date }) where !hasAction(incoming.id) {
            record(incoming.change, id: incoming.id, date: incoming.date)
        }
        let made = insertedModelsArray.filter { !before.contains(ObjectIdentifier($0)) }
        guard !made.isEmpty else { return [] }
        try save() // the copies' identifiers are final once saved
        return made.compactMap { LinkCopy($0) }
    }

    /// Drops each copy whose original iCloud brought, and saves. A workout's sets, and the end and Health id only its copy
    /// has, go to the original first. It records nothing: the log holds each change once, and so does the model again.
    /// Returns the copies still waiting. One that's gone, deleted here or by a change from elsewhere, waits no more.
    func dropCopies(_ copies: [LinkCopy]) throws -> [LinkCopy] {
        // Workouts first, so their sets move to the original before a set's copy goes.
        let ordered = copies.filter { $0.kind == .workout } + copies.filter { $0.kind != .workout }
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
            }
        }
        if hasChanges { try save() }
        return waiting
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
