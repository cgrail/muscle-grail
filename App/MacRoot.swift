#if os(macOS)
import Core
import SwiftData
import SwiftUI

/// The Mac app laid out like Apple Music: a sidebar with training, history, the exercise library, all plans at a glance
/// and every plan as a playlist, and the selected page beside it.
struct MacRootView: View {
    enum Page: Hashable { case train, history, exercises, changes, overview, plan(Plan) }

    @Environment(\.modelContext) private var context
    @Query(sort: \Plan.order) private var plans: [Plan]
    @Query(Action.newer) private var newer: [Action]
    @State private var page: Page?
    @State private var lastPlan: Plan? // the one Single plan opens

    var body: some View {
        let shared = plans.filter { PartnerStatus.shared.plans.contains($0.id) }
        NavigationSplitView {
            List(selection: $page) {
                Label("Train", systemImage: "figure.strengthtraining.traditional").tag(Page.train)
                Label("History", systemImage: "clock").tag(Page.history)
                Label("All plans", systemImage: "rectangle.split.3x1").tag(Page.overview)
                Section("Library") {
                    Label("Exercises", systemImage: "dumbbell").tag(Page.exercises)
                    Label("Changes", systemImage: "clock.arrow.circlepath").tag(Page.changes)
                }
                if shared.isEmpty {
                    Section("Plans") { rows(plans) }
                } else {
                    Section("Shared plans") { rows(shared) }
                    Section("My plans") { rows(plans.filter { !shared.contains($0) }) }
                }
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
            case .plan, nil: ContentUnavailableView("Choose a plan", systemImage: "list.bullet.clipboard") // a sync or restore deleted it
            }
        }
        .task { if page == nil { page = plans.first.map(Page.plan) ?? .train } }
        .onChange(of: page) { if case .plan(let plan) = page { lastPlan = plan } }
    }

    /// Plans as playlists, each with its exercise count. Reordering one section keeps the others' places in the one plan list.
    private func rows(_ section: [Plan]) -> some View {
        let locked = !newer.isEmpty
        return ForEach(section) { plan in
            Label {
                HStack {
                    Text(plan.title)
                    Spacer()
                    PlanSyncBadge(plan: plan)
                }
            } icon: {
                PlanArtwork(plan: plan, size: 20)
            }
            .badge(plan.sortedItems.count)
            .tag(Page.plan(plan))
            .contextMenu {
                PlanSharing(plan: plan)
                Button("Delete", systemImage: "trash", role: .destructive) { delete(plan) }.disabled(locked)
            }
        }
        .onMove { source, destination in
            var moved = section
            moved.move(fromOffsets: source, toOffset: destination)
            var reordered = moved.makeIterator()
            context.record(.reorder(ids: plans.map { section.contains($0) ? reordered.next()!.id : $0.id }))
        }
        .moveDisabled(locked)
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

    private func delete(_ plan: Plan) {
        if page == .plan(plan) { page = nil }
        context.deletePlan(plan)
    }
}

/// A plan's artwork, like a playlist's: its first exercise's photo.
struct PlanArtwork: View {
    let plan: Plan
    let size: Double

    var body: some View {
        ExerciseThumbnail(id: plan.sortedItems.first?.exerciseID ?? "", size: size, placeholder: "list.bullet.clipboard")
    }
}

/// An exercise's photo: the user's own, else the bundled one, else a symbol.
struct ExerciseThumbnail: View {
    @Query private var entries: [CatalogEntry]
    private let id: String
    private let size: Double
    private let placeholder: String

    init(id: String, size: Double, placeholder: String = "dumbbell") {
        (self.id, self.size, self.placeholder) = (id, size, placeholder)
        _entries = Query(filter: #Predicate { $0.id == id })
    }

    var body: some View {
        Group {
            if let image = entries.first?.photo.flatMap(Photo.image) {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else if let url = CatalogExercise.byID[id]?.imageURL {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { symbol }
            } else {
                symbol
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size / 8))
        .accessibilityHidden(true)
    }

    private var symbol: some View {
        Image(systemName: placeholder).font(.system(size: size * 0.45)).foregroundStyle(.secondary)
            .frame(width: size, height: size).background(.quaternary)
    }
}
#endif
