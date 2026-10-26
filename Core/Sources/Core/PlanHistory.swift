import Combine
import Foundation
import SwiftData
import SwiftUI

/// One entry of the plans' history: a plan change, or edits of the same kind to the same thing in a row.
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
    /// Edits in a row with the same key show as one entry; nil never merges.
    fileprivate let key: String?
}

public extension PlanChange {
    /// The changes of `plan`, or of every plan, newest first. Walks the whole log in a context of its own, so call it off the main actor.
    static func history(_ container: ModelContainer, plan: UUID? = nil) throws -> [PlanChange] {
        let context = ModelContext(container)
        var walk = Walk(context: context)
        var changes: [PlanChange] = []
        for action in try context.fetch(FetchDescriptor<Action>(sortBy: [SortDescriptor(\.date)])) {
            guard let change = action.change, let entry = walk.describe(change) else { continue }
            if let key = entry.key, let last = changes.last, last.key == key, last.author == action.author {
                changes[changes.count - 1].text = entry.text
                changes[changes.count - 1].date = action.date
            } else {
                changes.append(PlanChange(id: action.id, date: action.date, author: action.author, plans: entry.plans,
                                          planName: entry.planName, text: entry.text, key: entry.key))
            }
        }
        return changes.filter { change in plan.map { change.plans.contains($0) } ?? true }.reversed()
    }
}

/// The log, walked oldest first, remembering what each plan and exercise was then.
private struct Walk {
    let context: ModelContext
    var plans: [UUID: String] = [:]
    var items: [UUID: (plan: UUID, exerciseID: String)] = [:]
    var names: [String: String] = [:]

    /// `change` in words, before it updates what the walk remembers. Nil for training and the catalog.
    mutating func describe(_ change: Change) -> (key: String?, plans: [UUID], planName: String, text: String)? {
        switch change {
        case let .addPlan(id, name, _):
            plans[id] = name
            return (nil, [id], title(id), String(localized: "Created the plan", bundle: .module))
        case let .renamePlan(id, name):
            defer { plans[id] = name }
            return ("rename \(id)", [id], title(id), String(localized: "Renamed to \(name)", bundle: .module))
        case let .deletePlan(id):
            return (nil, [id], title(id), String(localized: "Deleted the plan", bundle: .module))
        case let .addExercise(id, plan, exerciseID, _):
            items[id] = (plan, exerciseID)
            return (nil, [plan], title(plan), String(localized: "Added \(name(exerciseID))", bundle: .module))
        case let .setTargets(id, sets, reps, weightKg):
            guard let item = items[id] else { return nil }
            let text = String(localized: "Set \(name(item.exerciseID)) to \(sets) × \(reps) at \(weightKg.formatted()) kg", bundle: .module)
            return ("targets \(id)", [item.plan], title(item.plan), text)
        case let .deleteExercise(id):
            guard let item = items.removeValue(forKey: id) else { return nil }
            return (nil, [item.plan], title(item.plan), String(localized: "Removed \(name(item.exerciseID))", bundle: .module))
        case let .reorder(ids):
            guard let first = ids.first else { return nil }
            if plans[first] != nil { return (nil, [], "", String(localized: "Reordered the plans", bundle: .module)) }
            guard let item = items[first] else { return nil }
            return (nil, [item.plan], title(item.plan), String(localized: "Reordered the exercises", bundle: .module))
        case let .moveExercise(id, plan, _):
            guard let item = items[id] else { return nil }
            items[id] = (plan, item.exerciseID)
            let text = String(localized: "Moved \(name(item.exerciseID)) from \(title(item.plan)) to \(title(plan))", bundle: .module)
            return (nil, [item.plan, plan], title(plan), text)
        case let .replaceExercise(id, exerciseID, _):
            guard let item = items[id] else { return nil }
            items[id] = (item.plan, exerciseID)
            let text = String(localized: "Replaced \(name(item.exerciseID)) with \(name(exerciseID))", bundle: .module)
            return (nil, [item.plan], title(item.plan), text)
        default:
            return nil
        }
    }

    func title(_ plan: UUID) -> String {
        let name = plans[plan] ?? ""
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
    let plan: UUID?
    @State private var changes: [PlanChange]?

    public init(plan: UUID? = nil) {
        self.plan = plan
    }

    public var body: some View {
        List(changes ?? []) { change in
            VStack(alignment: .leading) {
                Text(verbatim: change.text)
                Text(verbatim: detail(change)).font(.caption).foregroundStyle(.secondary)
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
