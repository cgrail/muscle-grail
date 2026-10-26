#if os(macOS)
import Core
import SwiftData
import SwiftUI

/// Every plan side by side, its exercises by name only, to move an exercise into another plan by dragging it there.
struct PlansOverview: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Plan.order) private var plans: [Plan]
    @Query(Action.newer) private var newer: [Action]
    let open: (Plan) -> Void
    @State private var forWhom: PendingEdit?

    var body: some View {
        ScrollView {
            if !newer.isEmpty { UpdateToEdit().padding([.horizontal, .top]) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                ForEach(plans) { plan in
                    PlanCard(plan: plan) { open(plan) } drop: { move($0, to: plan) }
                }
            }
            .padding()
        }
        .forWhom($forWhom)
        .navigationTitle("All plans")
        .navigationSubtitle("Drag an exercise onto another plan to move it.")
    }

    /// Moves the dragged exercise, by its id, to the end of `plan`, with its sets, reps and weight.
    private func move(_ id: String, to plan: Plan) -> Bool {
        guard newer.isEmpty, let item = plans.flatMap({ $0.items ?? [] }).first(where: { $0.id.uuidString == id }),
              item.plan != plan, item.ownedBy != .partner else { return false }
        ForWhom.edit(item.plan, item, asking: $forWhom) { context.move(item, to: plan, forBoth: $0) }
        return true
    }
}

/// A plan as a card: artwork, name, what it trains, then its exercises by name. It takes exercises dropped on it.
private struct PlanCard: View {
    let plan: Plan
    let open: () -> Void
    let drop: (String) -> Bool
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: open) {
                HStack(spacing: 10) {
                    PlanArtwork(plan: plan, size: 44)
                    VStack(alignment: .leading) {
                        HStack {
                            Text(plan.title).font(.headline)
                            SharedBadge(plan: plan)
                        }
                        if let focus = plan.focus {
                            Text(verbatim: focus).font(.caption).foregroundStyle(.tint)
                        }
                        Text("\(plan.sortedItems.count) exercises").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Divider()
            ForEach(plan.sortedItems) { item in
                HStack {
                    ExerciseThumbnail(id: item.exerciseID, size: 20)
                    VStack(alignment: .leading) {
                        ExerciseName(item.exerciseID).lineLimit(1)
                        OwnerNote(item: item)
                    }
                }
                .foregroundStyle(item.ownedBy == .partner ? .secondary : .primary)
                .draggable(item.id.uuidString)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(.tint, lineWidth: 2).opacity(targeted ? 1 : 0) }
        .dropDestination(for: String.self) { ids, _ in ids.first.map(drop) ?? false } isTargeted: { targeted = $0 }
    }
}
#endif
