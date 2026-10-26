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

    var body: some View {
        let locked = !newer.isEmpty
        NavigationSplitView {
            List(selection: $page) {
                Label("Train", systemImage: "figure.strengthtraining.traditional").tag(Page.train)
                Label("History", systemImage: "clock").tag(Page.history)
                Section("Library") {
                    Label("Exercises", systemImage: "dumbbell").tag(Page.exercises)
                    Label("Changes", systemImage: "clock.arrow.circlepath").tag(Page.changes)
                }
                Section("Plans") {
                    Label("All plans", systemImage: "square.grid.2x2").tag(Page.overview)
                    ForEach(plans) { plan in
                        Label {
                            HStack {
                                Text(plan.title)
                                Spacer()
                                SharedBadge(plan: plan)
                            }
                        } icon: {
                            PlanArtwork(plan: plan, size: 20)
                        }
                        .tag(Page.plan(plan))
                        .contextMenu {
                            PlanSharing(plan: plan)
                            Button("Delete", systemImage: "trash", role: .destructive) { delete(plan) }.disabled(locked)
                        }
                    }
                    .onMove { context.reorder(plans, fromOffsets: $0, toOffset: $1) }
                    .moveDisabled(locked)
                }
            }
            .safeAreaInset(edge: .bottom) {
                SyncStatusView().font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            .toolbar {
                Button("New Plan", systemImage: "plus") { page = .plan(context.addPlan()) }.disabled(locked)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            switch page {
            case .train: TrainView()
            case .history: HistoryView()
            case .exercises: ExercisesLibrary()
            case .changes: PlanChanges()
            case .overview: PlansOverview { page = .plan($0) }
            case .plan(let plan) where plans.contains(plan): PlanPage(plan: plan).id(plan.id)
            case .plan, nil: ContentUnavailableView("Choose a plan", systemImage: "list.bullet.clipboard") // a sync or restore deleted it
            }
        }
        .task { if page == nil { page = plans.first.map(Page.plan) ?? .train } }
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
