import Core
import SwiftData
import SwiftUI

@main
struct MuscleGrailApp: App {
    let container: ModelContainer
    #if os(macOS)
    @State private var claude: ClaudeConnection
    #endif

    init() {
        _ = SyncMonitor.shared // listen before the store's first sync event
        do {
            container = try Store.makeContainer()
        } catch {
            fatalError("Could not open the store: \(error)")
        }
        #if os(iOS)
        Health.observeSteps { await SyncMonitor.shared.waitUntilIdle() }
        #else
        _claude = State(initialValue: ClaudeConnection(context: container.mainContext))
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
        #if os(macOS)
        Settings { ClaudeSettings().environment(claude) }
        #endif
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Train", systemImage: "figure.strengthtraining.traditional") { TrainView() }
            Tab("Plans", systemImage: "list.bullet.clipboard") { PlansView() }
            Tab("History", systemImage: "clock") { HistoryView() }
        }
        .tabViewStyle(.sidebarAdaptable)
        #if os(iOS)
        .task {
            await Health.requestAuthorization()
            Health.observeSteps { await SyncMonitor.shared.waitUntilIdle() }
        }
        #else
        .toolbar { ToolbarItem(placement: .status) { SyncStatusView() } }
        #endif
    }
}
