import Combine
import Foundation
import SwiftData
import SwiftUI

/// One entry of the plans' history: a plan change, or edits of the same kind to the same thing in a row, or one undo.
public struct PlanChange: Identifiable, Equatable, Sendable {
    public let id: UUID
    public fileprivate(set) var date: Date
    /// Who made it: nil for you, else the training partner's name.
    public let author: String?
    /// The plans it concerns: two for a move, none for reordering the plans.
    public let plans: [UUID]
    /// The plan's name when it happened.
    public let planName: String
    public fileprivate(set) var text: String
    /// False once what it changed is gone, or for a deletion, once it's back.
    public fileprivate(set) var canUndo = false
    /// Edits in a row with the same key show as one entry; nil never merges.
    fileprivate let key: String?
    fileprivate let batch: UUID?
    /// The changes that reverse it, newest first.
    fileprivate var undo: [Change]
    /// What its undo needs to still exist, and what it brings back, so must be gone.
    fileprivate var needs: [UUID]
    fileprivate var absent: [UUID]
}

public extension PlanChange {
    /// The changes of `plan`, or of every plan, newest first. Walks the whole log in a context of its own, so call it off the main actor.
    static func history(_ container: ModelContainer, plan: UUID? = nil) throws -> [PlanChange] {
        let context = ModelContext(container)
        var walk = Walk(context: context)
        var changes: [PlanChange] = []
        for action in try context.fetch(FetchDescriptor<Action>(sortBy: [SortDescriptor(\.date)])) {
            guard let change = action.change, let step = walk.step(change) else { continue }
            if let last = changes.last, last.author == action.author, joins(step, action.batch, last) {
                let index = changes.count - 1
                if action.batch == nil { changes[index].text = step.text } // a batch reads as its first change
                changes[index].date = action.date
                changes[index].undo = step.undo + last.undo
                changes[index].needs += step.needs
                changes[index].absent += step.absent
            } else {
                changes.append(PlanChange(id: action.id, date: action.date, author: action.author, plans: step.plans, planName: step.planName,
                                          text: step.text, key: step.key, batch: action.batch, undo: step.undo, needs: step.needs, absent: step.absent))
            }
        }
        // The walk ends where the store is now.
        for index in changes.indices {
            changes[index].canUndo = changes[index].needs.allSatisfy(walk.exists) && !changes[index].absent.contains(where: walk.exists)
        }
        return changes.filter { change in plan.map { change.plans.contains($0) } ?? true }.reversed()
    }
}

public extension ModelContext {
    /// Records the changes that reverse `change`, as one batch, so the undo is one entry in the history and can be undone too.
    func undo(_ change: PlanChange) {
        let batch = UUID()
        for reverse in change.undo { record(reverse, batch: batch) }
    }
}

/// Whether a change joins the entry before it: the same undo, or another edit of the same thing in a row.
private func joins(_ step: Step, _ batch: UUID?, _ last: PlanChange) -> Bool {
    if let batch { return batch == last.batch }
    return step.key != nil && step.key == last.key && last.batch == nil
}

/// A change in words, and what reverses it.
private struct Step {
    var key: String?
    var plans: [UUID]
    var planName: String
    var text: String
    var undo: [Change]
    var needs: [UUID]
    var absent: [UUID] = []
}

/// The log, walked oldest first, applied to a model of the plans as `apply` changes them, to say what each change did.
private struct Walk {
    struct PlanState { var name: String, order: Int }
    struct ItemState { var plan: UUID, exerciseID: String, order: Int, sets = 3, reps = 10, weightKg = 0.0 }

    let context: ModelContext
    var plans: [UUID: PlanState] = [:]
    var items: [UUID: ItemState] = [:]
    var names: [String: String] = [:]

    func exists(_ id: UUID) -> Bool { plans[id] != nil || items[id] != nil }

    /// `change` in words and what reverses it, from the state before; then the state after. Nil for training and the catalog.
    mutating func step(_ change: Change) -> Step? {
        switch change {
        case let .addPlan(id, name, order):
            plans[id] = PlanState(name: name, order: order)
            return Step(plans: [id], planName: title(id), text: String(localized: "Created the plan", bundle: .module), undo: [.deletePlan(id: id)], needs: [id])
        case let .renamePlan(id, name):
            guard let plan = plans[id] else { return nil }
            defer { plans[id]?.name = name }
            return Step(key: "rename \(id)", plans: [id], planName: title(id), text: String(localized: "Renamed to \(name)", bundle: .module),
                        undo: [.renamePlan(id: id, name: plan.name)], needs: [id])
        case let .deletePlan(id):
            guard let plan = plans[id] else { return nil }
            let planName = title(id)
            let gone = items.filter { $0.value.plan == id }.sorted { $0.value.order < $1.value.order }
            plans[id] = nil
            for (item, _) in gone { items[item] = nil }
            let undo = [Change.addPlan(id: id, name: plan.name, order: plan.order)] + gone.flatMap { add($0.key, $0.value) }
            return Step(plans: [id], planName: planName, text: String(localized: "Deleted the plan", bundle: .module), undo: undo, needs: [], absent: [id])
        case let .addExercise(id, plan, exerciseID, order):
            var item = items[id] ?? ItemState(plan: plan, exerciseID: exerciseID, order: order)
            (item.plan, item.exerciseID, item.order) = (plan, exerciseID, order)
            items[id] = item
            return Step(plans: [plan], planName: title(plan), text: String(localized: "Added \(name(exerciseID))", bundle: .module),
                        undo: [.deleteExercise(id: id)], needs: [id])
        case let .setTargets(id, sets, reps, weightKg):
            guard let item = items[id] else { return nil }
            items[id]?.sets = sets
            items[id]?.reps = reps
            items[id]?.weightKg = weightKg
            let text = String(localized: "Set \(name(item.exerciseID)) to \(sets) × \(reps) at \(weightKg.formatted()) kg", bundle: .module)
            return Step(key: "targets \(id)", plans: [item.plan], planName: title(item.plan), text: text,
                        undo: [.setTargets(id: id, sets: item.sets, reps: item.reps, weightKg: item.weightKg)], needs: [id])
        case let .deleteExercise(id):
            guard let item = items.removeValue(forKey: id) else { return nil }
            return Step(plans: [item.plan], planName: title(item.plan), text: String(localized: "Removed \(name(item.exerciseID))", bundle: .module),
                        undo: add(id, item), needs: [item.plan], absent: [id])
        case let .reorder(ids):
            guard let first = ids.first, exists(first) else { return nil }
            let undo = [Change.reorder(ids: ids.sorted { order($0) < order($1) })]
            for (index, id) in ids.enumerated() {
                plans[id]?.order = index
                items[id]?.order = index
            }
            guard let plan = items[first]?.plan else {
                return Step(plans: [], planName: "", text: String(localized: "Reordered the plans", bundle: .module), undo: undo, needs: [first])
            }
            return Step(plans: [plan], planName: title(plan), text: String(localized: "Reordered the exercises", bundle: .module), undo: undo, needs: [first])
        case let .moveExercise(id, plan, order):
            guard let item = items[id], plans[plan] != nil else { return nil }
            items[id]?.plan = plan
            items[id]?.order = order
            let text = String(localized: "Moved \(name(item.exerciseID)) from \(title(item.plan)) to \(title(plan))", bundle: .module)
            return Step(plans: [item.plan, plan], planName: title(plan), text: text, undo: [.moveExercise(id: id, plan: item.plan, order: item.order)],
                        needs: [id, item.plan])
        case let .replaceExercise(id, exerciseID, weightKg):
            guard let item = items[id] else { return nil }
            items[id]?.exerciseID = exerciseID
            items[id]?.weightKg = weightKg
            let text = String(localized: "Replaced \(name(item.exerciseID)) with \(name(exerciseID))", bundle: .module)
            return Step(plans: [item.plan], planName: title(item.plan), text: text,
                        undo: [.replaceExercise(id: id, exerciseID: item.exerciseID, weightKg: item.weightKg)], needs: [id])
        default:
            return nil
        }
    }

    /// The changes that bring back a removed exercise, with its id and targets.
    func add(_ id: UUID, _ item: ItemState) -> [Change] {
        [.addExercise(id: id, plan: item.plan, exerciseID: item.exerciseID, order: item.order),
         .setTargets(id: id, sets: item.sets, reps: item.reps, weightKg: item.weightKg)]
    }

    func order(_ id: UUID) -> Int { plans[id]?.order ?? items[id]?.order ?? 0 }

    func title(_ plan: UUID) -> String {
        let name = plans[plan]?.name ?? ""
        return name.isEmpty ? String(localized: "Untitled", bundle: .module) : name
    }

    /// Fetched once per exercise: typing a weight records an action per key.
    mutating func name(_ exerciseID: String) -> String {
        if let name = names[exerciseID] { return name }
        let name = context.exerciseName(exerciseID)
        names[exerciseID] = name
        return name
    }
}

/// The history of one plan's changes, or of every plan's, newest first. It reloads whenever the store saves.
public struct PlanChanges: View {
    @Environment(\.modelContext) private var context
    @Query(Action.newer) private var newer: [Action]
    let plan: UUID?
    @State private var changes: [PlanChange]?

    public init(plan: UUID? = nil) {
        self.plan = plan
    }

    public var body: some View {
        List(changes ?? []) { change in
            HStack {
                VStack(alignment: .leading) {
                    Text(verbatim: change.text)
                    Text(verbatim: detail(change)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if change.canUndo {
                    Button {
                        context.undo(change)
                        try? context.save() // the history reads what's saved
                    } label: {
                        Text("Undo", bundle: .module)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!newer.isEmpty)
                }
            }
        }
        .overlay {
            if changes?.isEmpty == true {
                ContentUnavailableView { Label { Text("No changes yet", bundle: .module) } icon: { Image(systemName: "clock.arrow.circlepath") } }
            }
        }
        .navigationTitle(Text("Changes", bundle: .module))
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: DispatchQueue.main)) { _ in Task { await load() } }
    }

    private func load() async {
        let (container, plan) = (context.container, plan)
        changes = await Task.detached { (try? PlanChange.history(container, plan: plan)) ?? [] }.value
    }

    /// Who and when, and in the history of every plan, which plan.
    private func detail(_ change: PlanChange) -> String {
        let who = change.author ?? String(localized: "You", bundle: .module)
        let when = change.date.formatted(.relative(presentation: .named))
        return (plan == nil && !change.planName.isEmpty ? [change.planName, who, when] : [who, when]).joined(separator: " · ")
    }
}
