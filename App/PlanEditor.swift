#if os(iOS)
import Core
import SwiftData
import SwiftUI

/// A plan on the iPhone in edit mode: its name a field to type in, its picture a button to choose another, the dice for
/// funny names, and its exercises as cards like training shows them. Select selects exercises to move to another plan
/// or delete, and drags them into order. Changes lists what changed in it. `onDone`, when given, goes back to training.
struct PlanEditor: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Plan.order) private var plans: [Plan]
    @Query(Action.newer) private var newer: [Action]
    let plan: Plan
    var onDone: (() -> Void)?
    @State private var editMode = EditMode.inactive
    @State private var selection = Set<UUID>()
    @State private var picking = false
    @State private var forWhom: PendingEdit?
    @State private var scrolled = false

    var body: some View {
        let locked = !newer.isEmpty
        let selecting = editMode.isEditing
        List(selection: selecting ? $selection : nil) { // outside Select, a tap beside the controls selects nothing
            Group {
                HStack {
                    PictureButton(plan: plan, size: 48)
                    TextField("Name", text: Binding { plan.name } set: { context.rename(plan, to: $0) })
                        .font(.largeTitle.bold())
                    FunnyNameButton(plan: plan).font(.title2)
                }
                .disabled(locked)
                if let motto = plan.motto { Text(verbatim: motto).italic().foregroundStyle(.secondary) }
                if locked { UpdateToEdit() }
                ForEach(plan.sortedItems) { item in
                    PlanItemCard(item: item, selecting: selecting, forWhom: $forWhom)
                        .disabled(locked || item.ownedBy == .partner)
                        .tag(item.id)
                }
                .onMove { context.reorder(plan.sortedItems, fromOffsets: $0, toOffset: $1) }
                .moveDisabled(locked)
                Button("Add exercise", systemImage: "plus") { picking = true }.disabled(locked || selecting)
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        }
        .listStyle(.plain)
        .navigationTitle(scrolled ? plan.title : "") // the first row shows it, large, until it scrolls away
        .navigationBarTitleDisplayMode(.inline)
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 40 } action: { scrolled = $1 }
        .toolbar {
            ToolbarItemGroup {
                NavigationLink { PlanChanges(plan: plan.id) } label: { Label("Changes", systemImage: "clock.arrow.circlepath") }
                SettingsButton() // for the sets and reps new exercises start with
                if selecting {
                    Button("Done") { withAnimation { editMode = .inactive } }
                } else {
                    Button("Select") { withAnimation { editMode = .active } }.disabled(locked)
                    if let onDone { Button("Done", action: onDone) }
                }
            }
            if selecting {
                ToolbarItem(placement: .bottomBar) {
                    Menu("Move to", systemImage: "arrow.turn.up.right") {
                        ForEach(plans.filter { $0 != plan }) { target in
                            Button(target.title) { editSelected { context.move($0, to: target, forBoth: $1) } }
                        }
                    }
                    .disabled(selection.isEmpty)
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Button("Delete", systemImage: "trash", role: .destructive) { editSelected { context.deleteExercise($0, forBoth: $1) } }
                        .disabled(selection.isEmpty)
                }
            }
        }
        .toolbar(selecting ? .hidden : .visible, for: .tabBar) // the selection's actions take its place, as in Photos
        .environment(\.editMode, $editMode)
        .sheet(isPresented: $picking) {
            ExercisePicker { id in ForWhom.edit(plan, asking: $forWhom) { context.addNew(id, to: plan, own: $0 ? nil : .mine) } }
        }
        .forWhom($forWhom)
    }

    /// Runs `edit` on each selected exercise in plan order, asking once for whom if any of them is for both.
    private func editSelected(_ edit: @escaping (PlanItem, _ forBoth: Bool) -> Void) {
        let items = plan.sortedItems.filter { selection.contains($0.id) }
        selection = []
        ForWhom.edit(plan, items.first { $0.ownedBy == .both } ?? items.first, asking: $forWhom) { forBoth in
            for item in items { edit(item, forBoth) }
        }
    }
}

/// An exercise as a card: its photo and name open its details, its sets × reps open to change them, its weight steps
/// unless it's a bodyweight move, and its badge switches it between for both and your own. The training partner's own shows greyed, without targets:
/// theirs stay on their devices. Its context menu replaces, moves or deletes it.
private struct PlanItemCard: View {
    @Environment(\.modelContext) private var context
    let item: PlanItem
    let selecting: Bool
    @Binding var forWhom: PendingEdit?
    @State private var showingDetail = false
    @State private var replacing = false

    var body: some View {
        let theirs = item.ownedBy == .partner
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button { showingDetail = true } label: {
                    HStack(spacing: 12) {
                        ExerciseThumbnail(id: item.exerciseID, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            ExerciseName(item.exerciseID).font(.headline)
                            if theirs {
                                OwnerNote(item: item)
                            } else if let detail = CatalogExercise.byID[item.exerciseID]?.detail {
                                Text(verbatim: detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                OwnerButton(item: item)
            }
            if !theirs {
                Divider()
                HStack(spacing: 8) {
                    TargetsButton(item: item)
                    Spacer(minLength: 0)
                    if item.showsWeight {
                        if let plan = item.plan, PartnerStatus.shared.plans.contains(plan.id) {
                            Text("You").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        WeightStepper(kg: Binding { item.targetWeightKg } set: { context.setTargets(item, weightKg: $0) }, exerciseID: item.exerciseID)
                            .fixedSize()
                    }
                }
            }
        }
        .allowsHitTesting(!selecting) // a tap selects the card instead
        .padding()
        .background(.fill.tertiary, in: .rect(cornerRadius: 20))
        .foregroundStyle(theirs ? .secondary : .primary)
        .contextMenu {
            Button("Replace with…", systemImage: "arrow.left.arrow.right") { replacing = true }
            MoveToPlan(item: item, forWhom: $forWhom)
            Button("Delete", systemImage: "trash", role: .destructive) {
                ForWhom.edit(item.plan, item, asking: $forWhom) { context.deleteExercise(item, forBoth: $0) }
            }
        }
        .sheet(isPresented: $showingDetail) { ExerciseDetail(id: item.exerciseID) }
        .sheet(isPresented: $replacing) {
            ExercisePicker(title: "Replace with") { id in ForWhom.edit(item.plan, item, asking: $forWhom) { context.replace(item, with: id, forBoth: $0) } }
        }
    }
}
#endif
