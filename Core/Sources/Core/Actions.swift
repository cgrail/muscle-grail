import Foundation
import SwiftData

/// A change to the model. Each one is stored in a log and then applied, so the logs can always rebuild the model.
/// Shipped cases are frozen: never rename a case or a label, give a new field an optional type, and bump `version`
/// with every new case or field. Training's cases (`startWorkout`, `logSet`, `deleteSet`, `finishWorkout`) stay
/// readable by every version, so an old app can always log in the gym.
public enum Change: Codable, Equatable, Sendable {
    /// The format this app writes. An app that finds actions of a higher one leaves editing to an update.
    public static let version = 2

    case addPlan(id: UUID, name: String, order: Int)
    case renamePlan(id: UUID, name: String)
    case deletePlan(id: UUID)
    case addExercise(id: UUID, plan: UUID, exerciseID: String, order: Int)
    case setTargets(id: UUID, sets: Int, reps: Int, weightKg: Double)
    case deleteExercise(id: UUID)
    /// Plans or exercises, in their new order.
    case reorder(ids: [UUID])
    /// An exercise into another plan, at `order`, with its targets. Version 2.
    case moveExercise(id: UUID, plan: UUID, order: Int)
    /// Another exercise in the same place, at `weightKg`. Version 2.
    case replaceExercise(id: UUID, exerciseID: String, weightKg: Double)
    case startWorkout(id: UUID, plan: UUID, start: Date)
    case logSet(id: UUID, workout: UUID, exerciseID: String, reps: Int, weightKg: Double, date: Date)
    case deleteSet(id: UUID)
    case finishWorkout(id: UUID, end: Date)
    case savedToHealth(workout: UUID, healthKitID: UUID)
    case deleteWorkout(id: UUID)
    // The catalog's changes, logged in its own store.
    case editExercise(id: String, name: String, details: String, videoURL: String)
    case setPhoto(id: String, photo: Data?)

    var isCatalog: Bool {
        switch self {
        case .editExercise, .setPhoto: true
        default: false
        }
    }
}

/// A log entry: `Action` in the gym store, `CatalogAction` in the catalog's.
public protocol ChangeRecord: PersistentModel {
    var id: UUID { get set }
    var date: Date { get set }
    var version: Int { get set }
    var payload: Data { get set }
    init()
}

extension Action: ChangeRecord {}
extension CatalogAction: ChangeRecord {}

public extension ChangeRecord {
    init(_ change: Change) {
        self.init()
        version = Change.version
        payload = (try? JSONEncoder().encode(change)) ?? Data()
    }

    /// Nil for a change from a newer version that this one can't read.
    var change: Change? { try? JSONDecoder().decode(Change.self, from: payload) }
}

public extension Action {
    /// Actions a newer app version recorded. While there are any, plans can't be edited here; training goes on.
    static var newer: FetchDescriptor<Action> {
        let current = Change.version
        var descriptor = FetchDescriptor<Action>(predicate: #Predicate { $0.version > current })
        descriptor.fetchLimit = 1
        return descriptor
    }
}

public extension CatalogAction {
    /// Catalog changes a newer app version recorded. While there are any, the catalog can't be edited here.
    static var newer: FetchDescriptor<CatalogAction> {
        let current = Change.version
        var descriptor = FetchDescriptor<CatalogAction>(predicate: #Predicate { $0.version > current })
        descriptor.fetchLimit = 1
        return descriptor
    }
}

public extension ModelContext {
    /// Stores `change` in its log and applies it. Every change to the model goes through here.
    /// The changes of one undo or restore share a `batch`, so the history shows them as one entry.
    func record(_ change: Change, batch: UUID? = nil) {
        if change.isCatalog {
            insert(CatalogAction(change))
        } else {
            let action = Action(change)
            action.batch = batch
            insert(action)
        }
        apply(change)
    }

    /// Re-applies both logs, oldest first, to `target`: into an empty store it rebuilds the model, and into this one it
    /// changes nothing. Changes this version can't read are skipped.
    func replay(into target: ModelContext) throws {
        let gym = try fetch(FetchDescriptor<Action>()).map { ($0.date, $0.change) }
        let catalog = try fetch(FetchDescriptor<CatalogAction>()).map { ($0.date, $0.change) }
        for (_, change) in (catalog + gym).sorted(by: { $0.0 < $1.0 }) {
            if let change { target.apply(change) }
        }
    }

    /// Applying a change twice changes nothing more, and a set creates its missing workout,
    /// so actions from several devices can arrive in any order.
    func apply(_ change: Change) {
        switch change {
        case let .addPlan(id, name, order):
            let plan = plan(id) ?? inserted(Plan(name: name, order: order))
            (plan.id, plan.name, plan.order) = (id, name, order)
        case let .renamePlan(id, name):
            plan(id)?.name = name
        case let .deletePlan(id):
            if let plan = plan(id) { delete(plan) }
        case let .addExercise(id, planID, exerciseID, order):
            let item = item(id) ?? inserted(PlanItem(exerciseID: exerciseID, order: order))
            (item.id, item.exerciseID, item.order, item.plan) = (id, exerciseID, order, plan(planID))
        case let .setTargets(id, sets, reps, weightKg):
            guard let item = item(id) else { return }
            (item.targetSets, item.targetReps, item.targetWeightKg) = (sets, reps, weightKg)
        case let .deleteExercise(id):
            if let item = item(id) { delete(item) }
        case let .moveExercise(id, planID, order):
            guard let item = item(id), let plan = plan(planID) else { return }
            (item.plan, item.order) = (plan, order)
        case let .replaceExercise(id, exerciseID, weightKg):
            guard let item = item(id) else { return }
            (item.exerciseID, item.targetWeightKg) = (exerciseID, weightKg)
        case let .reorder(ids):
            for (index, id) in ids.enumerated() {
                let row: (any Ordered)? = plan(id) ?? item(id)
                row?.order = index
            }
        case let .startWorkout(id, planID, start):
            let workout = workout(id, orNewAt: start)
            (workout.start, workout.plan) = (start, plan(planID))
        case let .logSet(id, workoutID, exerciseID, reps, weightKg, date):
            let set = loggedSet(id) ?? inserted(LoggedSet(exerciseID: exerciseID, reps: reps, weightKg: weightKg))
            (set.id, set.date, set.workout) = (id, date, workout(workoutID, orNewAt: date))
        case let .deleteSet(id):
            if let set = loggedSet(id) { delete(set) }
        case let .finishWorkout(id, end):
            workout(id)?.end = end
        case let .savedToHealth(workoutID, healthKitID):
            workout(workoutID)?.healthKitID = healthKitID
        case let .deleteWorkout(id):
            if let workout = workout(id) { delete(workout) }
        case let .editExercise(id, name, details, videoURL):
            let entry = catalogEntry(id) ?? inserted(CatalogEntry(id: id))
            (entry.name, entry.details, entry.videoURL) = (name, details, videoURL)
        case let .setPhoto(id, photo):
            (catalogEntry(id) ?? inserted(CatalogEntry(id: id))).photo = photo
        }
    }
}

extension ModelContext {
    func plan(_ id: UUID) -> Plan? { first(#Predicate { $0.id == id }) }
    func item(_ id: UUID) -> PlanItem? { first(#Predicate { $0.id == id }) }
    func workout(_ id: UUID) -> Workout? { first(#Predicate { $0.id == id }) }
    func loggedSet(_ id: UUID) -> LoggedSet? { first(#Predicate { $0.id == id }) }
    func catalogEntry(_ id: String) -> CatalogEntry? { first(#Predicate { $0.id == id }) }

    private func workout(_ id: UUID, orNewAt start: Date) -> Workout {
        if let workout = workout(id) { return workout }
        let workout = inserted(Workout())
        (workout.id, workout.start) = (id, start)
        return workout
    }

    private func first<T: PersistentModel>(_ predicate: Predicate<T>) -> T? {
        try? fetch(FetchDescriptor(predicate: predicate)).first
    }

    private func inserted<T: PersistentModel>(_ model: T) -> T {
        insert(model)
        return model
    }
}
