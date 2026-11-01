import Core
import HealthKit
import SwiftData
import SwiftUI

/// The workout's exercises as cards, each with its next set and how many sets are done. A card opens the exercise to
/// log it; finishing shows a summary first, as does logging the last set of the last exercise. A plan picked to train has
/// no workout, here or in Health, until its first set is logged, and can be left until then.
struct WatchWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let plan: Plan?
    @State private var workout: Workout?
    @State private var session = WorkoutSession()
    @State private var exercise: PlanItem?
    @State private var finishing = false

    init(plan: Plan?, workout: Workout?) {
        self.plan = plan
        _workout = State(initialValue: workout)
    }

    var body: some View {
        List {
            ForEach(plan?.trainedItems ?? []) { item in
                Button { exercise = item } label: { ExerciseCard(item: item, workout: workout) }
            }
            if workout != nil {
                Button("Finish workout", systemImage: "flag.checkered") { finishing = true }
            }
        }
        .navigationTitle(workout?.title ?? plan?.title ?? "")
        .navigationBarBackButtonHidden(workout != nil)
        .navigationDestination(item: $exercise) { item in
            ExerciseView(item: item, workout: $workout) {
                exercise = nil
                if workout?.isComplete == true { finishing = true }
            }
        }
        .sheet(isPresented: $finishing) {
            if let workout {
                FinishView(workout: workout) {
                    context.finish(workout)
                    session.end { id in
                        if let id { context.savedToHealth(workout, as: id) }
                    }
                    finishing = false
                    dismiss()
                }
            }
        }
        .onChange(of: workout != nil, initial: true) { if workout != nil { session.start() } }
    }
}

/// An exercise in the workout list: its name, the next set as prefilled, and how many of its sets are done.
private struct ExerciseCard: View {
    @Environment(\.modelContext) private var context
    let item: PlanItem
    let workout: Workout?

    var body: some View {
        let done = workout?.sets(of: item.exerciseID).count ?? 0
        let next = context.nextSet(for: item, in: workout)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                ExerciseName(item.exerciseID).font(.headline)
                Spacer(minLength: 4)
                if done >= item.targetSets {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel(Text("Done"))
                } else {
                    Text("\(done)/\(item.targetSets) sets")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(done > 0 ? Color.green : Color.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background((done > 0 ? Color.green : Color.gray).opacity(0.2), in: .capsule)
                }
            }
            HStack {
                Text("\(next.reps) reps").foregroundStyle(.secondary)
                Spacer()
                if next.weightKg > 0 {
                    Text(verbatim: context.weightUnit(of: item.exerciseID).format(next.weightKg)).foregroundStyle(.cyan)
                }
            }
            .font(.footnote.monospacedDigit())
        }
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
