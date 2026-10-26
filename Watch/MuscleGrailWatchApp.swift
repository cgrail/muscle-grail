import Core
import SwiftData
import SwiftUI
import WidgetKit

@main
struct MuscleGrailWatchApp: App {
    @State private var store: OpenStore
    @State private var path: [Workout] = []

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
                }
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
