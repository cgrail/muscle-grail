import Core
import HealthKit
import SwiftData
import SwiftUI

/// One page per exercise, then a finish page.
struct WatchWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let workout: Workout
    @State private var session = WorkoutSession()

    var body: some View {
        TabView {
            ForEach(workout.plan?.sortedItems ?? []) { item in
                List { ExerciseSection(item: item, workout: workout) }
            }
            Button("Finish", systemImage: "checkmark") {
                context.finish(workout)
                session.end { id in
                    if let id { context.savedToHealth(workout, as: id) }
                }
                dismiss()
            }
            .tint(.green)
        }
        .tabViewStyle(.verticalPage)
        .navigationTitle(workout.title)
        .navigationBarBackButtonHidden()
        .onAppear { session.start() }
    }
}

/// Keeps the app frontmost and running for the whole workout, and records heart rate and calories into Health.
final class WorkoutSession: NSObject, HKWorkoutSessionDelegate {
    private var session: HKWorkoutSession?
    private var onSaved: ((UUID?) -> Void)?

    func start() {
        guard session == nil else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        guard let session = try? HKWorkoutSession(healthStore: Health.store, configuration: config) else { return }
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: Health.store, workoutConfiguration: config)
        session.delegate = self
        self.session = session
        session.startActivity(with: .now)
        builder.beginCollection(withStart: .now) { _, _ in }
    }

    func end(onSaved: @escaping (UUID?) -> Void) {
        self.onSaved = onSaved
        session?.end()
    }

    nonisolated func workoutSession(_ session: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended else { return }
        let builder = session.associatedWorkoutBuilder()
        builder.endCollection(withEnd: date) { _, _ in
            builder.finishWorkout { workout, _ in
                let id = workout?.uuid
                Task { @MainActor in self.onSaved?(id) }
            }
        }
    }

    nonisolated func workoutSession(_ session: HKWorkoutSession, didFailWithError error: Error) {}
}
