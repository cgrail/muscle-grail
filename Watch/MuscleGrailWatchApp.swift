import Core
import SwiftData
import SwiftUI
import WidgetKit

@main
struct MuscleGrailWatchApp: App {
    @State private var store: OpenStore
    @State private var path: [Workout] = []
    @State private var showingActivity = false

    init() {
        _ = SyncMonitor.shared // listen before the store's first sync event
        _store = State(initialValue: OpenStore())
        Self.observeSteps()
    }

    static func observeSteps() {
        Health.observeSteps {
            WidgetCenter.shared.reloadAllTimelines() // new steps for the complication
            await SyncMonitor.shared.waitUntilIdle()
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container = store.container {
                NavigationStack(path: $path) {
                    WorkoutPicker { path = [$0] }
                        .navigationDestination(for: Workout.self) { WatchWorkoutView(workout: $0) }
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                NavigationLink { InfoView() } label: { Label("Info", systemImage: "info.circle") }
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Activity", systemImage: "figure.walk") { showingActivity = true }
                            }
                        }
                }
                // A sheet, so the complication opens it over a running workout too.
                .sheet(isPresented: $showingActivity) { NavigationStack { ActivityView() } }
                .onOpenURL { _ in showingActivity = true } // the complication's link, the only one
                .task {
                    await Health.requestAuthorization()
                    Self.observeSteps()
                }
                .modelContainer(container)
            } else {
                UnreadableStore(store)
            }
        }
    }
}
