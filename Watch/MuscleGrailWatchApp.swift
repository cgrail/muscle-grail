import Core
import SwiftData
import SwiftUI
import WidgetKit

@main
struct MuscleGrailWatchApp: App {
    let container: ModelContainer
    @State private var path: [Workout] = []

    init() {
        _ = SyncMonitor.shared // listen before the store's first sync event
        do {
            container = try Store.makeContainer()
        } catch {
            fatalError("Could not open the store: \(error)")
        }
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
            NavigationStack(path: $path) {
                WorkoutPicker { path = [$0] }
                    .navigationDestination(for: Workout.self) { WatchWorkoutView(workout: $0) }
            }
            .task {
                await Health.requestAuthorization()
                Self.observeSteps()
            }
        }
        .modelContainer(container)
    }
}
