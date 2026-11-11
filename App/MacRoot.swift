#if os(macOS)
import Core
import SwiftData
import SwiftUI

/// The Mac app laid out like Apple Music: a sidebar with training, history, the exercises and the changes, then all plans
/// at a glance and every plan as a playlist, and the selected page beside it. Several plans can be selected to delete them at once.
struct MacRootView: View {
    enum Page: Hashable { case train, history, exercises, changes, overview, plan(Plan) }

    @Environment(\.modelContext) private var context
    @Query(sort: \Plan.order) private var plans: [Plan]
    @Query(Action.newer) private var newer: [Action]
    @State private var selection = Set<Page>()
    @State private var lastPlan: Plan? // the one Single plan opens
    @State private var renaming: Plan?
    @State private var newName = ""
    @FocusState private var naming: Bool
    @State private var deleting: [Plan] = []

    /// The one page selected: none while several are.
    private var page: Page? {
        get { selection.count == 1 ? selection.first : nil }
        nonmutating set { selection = newValue.map { [$0] } ?? [] }
    }

    var body: some View {
        let shared = plans.filter { PartnerStatus.shared.plans.contains($0.id) }
        NavigationSplitView {
            List(selection: $selection) {
                Label("Train", systemImage: "figure.strengthtraining.traditional").tag(Page.train)
                Label("History", systemImage: "clock").tag(Page.history)
                Label("Exercises", systemImage: "dumbbell").tag(Page.exercises)
                Label("Changes", systemImage: "clock.arrow.circlepath").tag(Page.changes)
                Section("Plans") {
                    Label("All plans", systemImage: "rectangle.split.3x1").tag(Page.overview)
                    if shared.isEmpty { rows(plans) }
                }
                if !shared.isEmpty {
                    Section("Shared plans") { rows(shared) }
                    Section("My plans") { rows(plans.filter { !shared.contains($0) }) }
                }
            }
            .contextMenu(forSelectionType: Page.self) { pages in
                let chosen = plans.filter { pages.contains(.plan($0)) }
                if !chosen.isEmpty { menu(chosen) }
            }
            .onDeleteCommand { if newer.isEmpty { ask(toDelete: plans.filter { selection.contains(.plan($0)) }) } }
            .confirmationDialog("Delete \(deleting.count) plans?", isPresented: Binding { !deleting.isEmpty } set: { if !$0 { deleting = [] } },
                                titleVisibility: .visible, presenting: deleting) { doomed in
                Button("Delete", role: .destructive) { delete(doomed) }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    TargetDefaultsPanel()
                    SyncStatusView().font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .toolbar {
                Button("New Plan", systemImage: "plus") { page = .plan(context.addPlan()) }.disabled(!newer.isEmpty)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            switch page {
            case .train: TrainView()
            case .history: HistoryView()
            case .exercises: ExercisesLibrary()
            case .changes: PlanChanges()
            case .overview: PlansOverview { page = .plan($0) }.toolbar { layoutPicker }
            case .plan(let plan) where plans.contains(plan): PlanPage(plan: plan).id(plan.id).toolbar { layoutPicker }
            case nil where selection.count > 1: ContentUnavailableView("\(selection.count) selected", systemImage: "checklist")
            case .plan, nil: ContentUnavailableView("Choose a plan", systemImage: "list.bullet.clipboard") // a sync or restore deleted it
            }
        }
        .task { if selection.isEmpty { page = plans.first.map(Page.plan) ?? .train } }
        .modifier(GymBookImporter())
        .onChange(of: page) { if case .plan(let plan) = page { lastPlan = plan } }
    }

    /// Plans as playlists, each with its exercise count. Reordering one section keeps the others' places in the one plan list.
    private func rows(_ section: [Plan]) -> some View {
        ForEach(section) { plan in
            Label {
                HStack {
                    if renaming == plan {
                        TextField("Name", text: $newName)
                            .focused($naming)
                            .task { naming = true }
                            .onSubmit(rename)
                            .onChange(of: naming) { if !naming { rename() } } // a click elsewhere keeps the name typed
                            .onExitCommand { renaming = nil }
                    } else {
                        Text(plan.title)
                    }
                    Spacer()
                    PlanSyncBadge(plan: plan)
                }
            } icon: {
                PlanPicture(plan, size: 20)
            }
            .badge(plan.sortedItems.count)
            .tag(Page.plan(plan))
        }
        .onMove { source, destination in
            var moved = section
            moved.move(fromOffsets: source, toOffset: destination)
            var reordered = moved.makeIterator()
            context.record(.reorder(ids: plans.map { section.contains($0) ? reordered.next()!.id : $0.id }))
        }
        .moveDisabled(!newer.isEmpty)
    }

    /// What a right click on plans offers: on one plan also renaming and sharing it.
    @ViewBuilder private func menu(_ chosen: [Plan]) -> some View {
        let locked = !newer.isEmpty
        Group {
            if let plan = chosen.first, chosen.count == 1 {
                Button("Rename", systemImage: "pencil") { (renaming, newName) = (plan, plan.name) }
            }
            Button("Duplicate", systemImage: "plus.square.on.square") { selection = Set(chosen.map { .plan(context.duplicate($0)) }) }
            Button("Funny name", systemImage: "dice") { chosen.forEach(context.rollFunnyName) }
        }
        .disabled(locked)
        if let plan = chosen.first, chosen.count == 1 { PlanSharing(plan: plan) }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { ask(toDelete: chosen) }.disabled(locked)
    }

    private func rename() {
        if let plan = renaming, newName != plan.name { context.rename(plan, to: newName) }
        renaming = nil
    }

    /// One plan goes at once, as Changes can bring it back; several ask first.
    private func ask(toDelete doomed: [Plan]) {
        if doomed.count > 1 { deleting = doomed } else { delete(doomed) }
    }

    private func delete(_ doomed: [Plan]) {
        selection.subtract(doomed.map(Page.plan))
        doomed.forEach(context.deletePlan)
    }

    /// Switches between every plan side by side and one plan on its own, like Finder's view buttons.
    private var layoutPicker: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Layout", selection: Binding { page == .overview } set: { board in
                page = board ? .overview : (plans.first { $0 == lastPlan } ?? plans.first).map(Page.plan)
            }) {
                Text("All plans").tag(true)
                Text("Single plan").tag(false)
            }
            .pickerStyle(.segmented)
        }
    }
}
#endif
