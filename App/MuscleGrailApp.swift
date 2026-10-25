import Core
import SwiftData
import SwiftUI

@main
struct MuscleGrailApp: App {
    let container: ModelContainer

    init() {
        _ = SyncMonitor.shared // listen before the store's first sync event
        do {
            container = try Store.makeContainer()
        } catch {
            fatalError("Could not open the store: \(error)")
        }
        #if os(iOS)
        Health.observeSteps { await SyncMonitor.shared.waitUntilIdle() }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            #if os(iOS)
            Tab("Train", systemImage: "figure.strengthtraining.traditional") { TrainView() }
            #endif
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
