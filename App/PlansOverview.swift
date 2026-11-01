#if os(macOS)
import Core
import SwiftData
import SwiftUI

/// Every plan as a column side by side, its exercises as cards with their sets, reps and weight. Drag an exercise onto
/// another column, or use Move to in its context menu, to move it there. While plans are shared, View as shows the shared plans
/// as the training partner trains them.
struct PlansOverview: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Plan.order) private var plans: [Plan]
    @Query(Action.newer) private var newer: [Action]
    let open: (Plan) -> Void
    @State private var forWhom: PendingEdit?
    @State private var adding: Plan?
    @State private var asPartner = false

    var body: some View {
        let status = PartnerStatus.shared
        let partnerView = asPartner && !status.plans.isEmpty
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(plans.filter { !partnerView || status.plans.contains($0.id) }) { plan in
                    PlanColumn(plan: plan, asPartner: partnerView, locked: !newer.isEmpty || partnerView, forWhom: $forWhom,
                               open: { open(plan) }, add: { adding = plan }, drop: { move($0, to: plan) })
                }
            }
            .padding()
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .safeAreaInset(edge: .top) {
            if !newer.isEmpty {
                UpdateToEdit().frame(maxWidth: .infinity, alignment: .leading).padding([.horizontal, .top])
            } else if partnerView {
                PartnerViewNote().frame(maxWidth: .infinity, alignment: .leading).padding([.horizontal, .top])
            }
        }
        .toolbar {
            if !status.plans.isEmpty {
                Picker("View as", selection: $asPartner) {
                    Text("You").tag(false)
                    if let partner = status.partner { Text(verbatim: partner).tag(true) } else { Text("Training partner").tag(true) }
                }
                .pickerStyle(.segmented)
            }
        }
        .sheet(item: $adding) { plan in
            ExercisePicker { id in ForWhom.edit(plan, asking: $forWhom) { context.addNew(id, to: plan, own: $0 ? nil : .mine) } }
        }
        .forWhom($forWhom)
        .navigationTitle("All plans")
        .navigationSubtitle("Drag an exercise onto another plan to move it.")
    }

    /// Moves the dragged exercise, by its id, to the end of `plan`, with its sets, reps and weight.
    private func move(_ id: String, to plan: Plan) -> Bool {
        guard newer.isEmpty, !asPartner, let item = plans.flatMap({ $0.items ?? [] }).first(where: { $0.id.uuidString == id }),
              item.plan != plan, item.ownedBy != .partner else { return false }
        ForWhom.edit(item.plan, item, asking: $forWhom) { context.move(item, to: plan, forBoth: $0) }
        return true
    }
}

/// Says what View as the training partner shows, and what it leaves out.
private struct PartnerViewNote: View {
    var body: some View {
        Group {
            if let partner = PartnerStatus.shared.partner {
                Text("The shared plans as \(partner) trains them. Sets, reps and weights stay personal, so they don't show here.")
            } else {
                Text("The shared plans as your training partner trains them. Sets, reps and weights stay personal, so they don't show here.")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

/// A plan as a column: its name, whether it's shared and its exercises as cards. It takes exercises dropped on it.
private struct PlanColumn: View {
    let plan: Plan
    let asPartner: Bool
    let locked: Bool
    @Binding var forWhom: PendingEdit?
    let open: () -> Void
    let add: () -> Void
    let drop: (String) -> Bool
    @State private var targeted = false

    var body: some View {
        let shared = PartnerStatus.shared.plans.contains(plan.id)
        let items = plan.sortedItems.filter { !asPartner || $0.ownedBy != .me }
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header(shared: shared, count: items.count)
                Divider()
                ForEach(items) { ExerciseCard(item: $0, shared: shared, asPartner: asPartner, locked: locked, forWhom: $forWhom) }
                if !locked {
                    Button(action: add) {
                        Label("Add exercise", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderless)
                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [4])) }
                }
            }
            .padding(12)
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(.tint, lineWidth: 2).opacity(targeted ? 1 : 0) }
            .dropDestination(for: String.self) { ids, _ in ids.first.map(drop) ?? false } isTargeted: { targeted = $0 }
        }
        .scrollIndicators(.never)
        .frame(width: 300)
    }

    private func header(shared: Bool, count: Int) -> some View {
        HStack(alignment: .top) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.title).font(.title3.bold())
                    HStack(spacing: 6) {
                        if shared {
                            Label("Shared", systemImage: "person.2.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.green.opacity(0.15), in: .capsule)
                        }
                        Text("\(count) exercises").font(.caption).foregroundStyle(.secondary)
                    }
                    if let focus = plan.focus {
                        Text(verbatim: focus).font(.caption).foregroundStyle(.tint)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Spacer()
            Button("Add exercise", systemImage: "plus", action: add)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(locked)
            if PartnerStatus.shared.sharing {
                Menu {
                    PlanSharing(plan: plan)
                } label: {
                    Image(systemName: "person.2")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.bottom, 4)
    }
}

/// An exercise as a card, its grip to drag it by: its name, sets and reps, and its weight to step. A button switches it
/// between for both and your own. The training partner's own shows greyed, without targets: theirs stay on their
/// devices. Its context menu moves or deletes it.
private struct ExerciseCard: View {
    @Environment(\.modelContext) private var context
    let item: PlanItem
    let shared: Bool
    let asPartner: Bool
    let locked: Bool
    @Binding var forWhom: PendingEdit?

    var body: some View {
        let theirs = item.ownedBy == .partner
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).accessibilityHidden(true)
                ExerciseName(item.exerciseID).font(.headline).lineLimit(1)
                Spacer(minLength: 0)
                OwnerButton(item: item).disabled(locked)
            }
            if !asPartner && !theirs {
                Divider()
                HStack(spacing: 8) {
                    TargetsButton(item: item).disabled(locked)
                    Spacer()
                    if shared { Text("You").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                    WeightStepper(kg: Binding { item.targetWeightKg } set: { context.setTargets(item, weightKg: $0) }, exerciseID: item.exerciseID)
                        .fixedSize()
                        .disabled(locked)
                }
            }
            if theirs && !asPartner { OwnerNote(item: item) }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.separator) }
        .foregroundStyle(theirs && !asPartner ? .secondary : .primary)
        .contextMenu {
            if !locked && !theirs {
                MoveToPlan(item: item, forWhom: $forWhom)
                Button("Delete", systemImage: "trash", role: .destructive) {
                    ForWhom.edit(item.plan, item, asking: $forWhom) { context.deleteExercise(item, forBoth: $0) }
                }
            }
        }
        .draggable(item.id.uuidString)
    }
}
#endif
