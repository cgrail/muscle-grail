import Combine
import Foundation
import SwiftData
import SwiftUI

/// The history of one plan's changes, or of every plan's, newest first. It reloads whenever the store saves.
public struct PlanChanges: View {
    @Environment(\.modelContext) private var context
    let plan: UUID?
    @State private var changes: [PlanChange]?

    public init(plan: UUID? = nil) {
        self.plan = plan
    }

    public var body: some View {
        let locked = ((try? context.fetchCount(Action.newer)) ?? 0) > 0
        List(changes ?? []) { change in
            HStack {
                VStack(alignment: .leading) {
                    Text(verbatim: change.text)
                    Text(verbatim: detail(change)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if change.canUndo {
                    Button { edit { context.undo(change) } } label: { Text("Undo", bundle: .module) }
                        .buttonStyle(.borderless)
                        .disabled(locked)
                }
                if change.canRestore {
                    Button { edit { context.restore(change) } } label: { Text("Restore", bundle: .module) }
                        .buttonStyle(.borderless)
                        .disabled(locked)
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
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: DispatchQueue.main)) { saved in
            if (saved.object as? ModelContext)?.container === context.container { Task { await load() } }
        }
    }

    /// Saves right away: the history reads what's saved.
    private func edit(_ change: () -> Void) {
        change()
        try? context.save()
    }

    private func load() async {
        let (container, plan) = (context.container, plan)
        let history = await Task.detached { (try? PlanChange.history(container, plan: plan)) ?? [] }.value
        withExtendedLifetime(container) {} // let go of it here, on the main actor: freed off it, its SwiftUI observers break
        changes = history
    }

    /// Who and when, and in the history of every plan, which plan.
    private func detail(_ change: PlanChange) -> String {
        let who = change.author ?? String(localized: "You", bundle: .module)
        let when = change.date.formatted(.relative(presentation: .named))
        return (plan == nil && !change.planName.isEmpty ? [change.planName, who, when] : [who, when]).joined(separator: " · ")
    }
}
