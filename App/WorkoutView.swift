import Core
import SwiftData
import SwiftUI

/// The running workout's exercises as cards, the next one to do outlined: tick a card to log its next set as prefilled,
/// or open it to log and adjust. Summary shows the workout before it ends, as does logging the last set of the last exercise.
struct WorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let workout: Workout
    @State private var exercise: PlanItem?
    @State private var finishing = false

    var body: some View {
        let items = workout.plan?.trainedItems ?? []
        let next = items.first { workout.sets(of: $0.exerciseID).count < $0.targetSets }
        ScrollView {
            VStack(spacing: 12) {
                ForEach(items) { item in
                    ExerciseCard(item: item, workout: workout, isNext: item == next) { exercise = item }
                }
            }
            .padding()
        }
        .navigationTitle(workout.title)
        .navigationSubtitle(workout.plan?.focus ?? "")
        .toolbar { Button("Summary") { finishing = true } }
        .navigationDestination(item: $exercise) { item in
            ExerciseView(item: item, workout: workout) {
                exercise = nil
                if workout.isComplete { finishing = true }
            }
        }
        .sheet(isPresented: $finishing) {
            NavigationStack {
                FinishView(workout: workout) {
                    context.finish(workout)
                    #if os(iOS) // the Mac has no HealthKit
                    Task {
                        if let id = await Health.save(workout) { context.savedToHealth(workout, as: id) }
                    }
                    #endif
                    finishing = false
                    dismiss()
                }
            }
        }
    }
}

/// An exercise in the workout: its name, the next set as prefilled and how many of its sets are done. The check logs
/// that set without opening the exercise.
private struct ExerciseCard: View {
    @Environment(\.modelContext) private var context
    let item: PlanItem
    let workout: Workout
    let isNext: Bool
    let open: () -> Void
    @State private var photo: CGImage?

    var body: some View {
        let done = workout.sets(of: item.exerciseID).count
        let next = context.nextSet(for: item, in: workout)
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 12) {
                    Group {
                        if let photo {
                            Image(decorative: photo, scale: 1).resizable().scaledToFill()
                        } else {
                            Image(systemName: "dumbbell").foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(.rect(cornerRadius: 10))
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        ExerciseName(item.exerciseID).font(.headline)
                        HStack(spacing: 6) {
                            if next.weightKg > 0 {
                                Text(verbatim: context.weightUnit(of: item.exerciseID).format(next.weightKg)).foregroundStyle(.cyan)
                                Text(verbatim: "·")
                            }
                            Text("\(next.reps) reps")
                        }
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(verbatim: "\(done)/\(item.targetSets)")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(done > 0 ? Color.green : Color.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background((done > 0 ? Color.green : Color.gray).opacity(0.2), in: .capsule)
                        .accessibilityLabel(Text("\(done)/\(item.targetSets) sets"))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if done >= item.targetSets {
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green).accessibilityLabel(Text("Done"))
            } else {
                Button("Log set", systemImage: "checkmark.circle") { context.tick(item, in: workout) }
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .buttonStyle(.borderless)
                    .tint(.green)
            }
        }
        .padding()
        .background(.fill.tertiary, in: .rect(cornerRadius: 20))
        .overlay {
            if isNext { RoundedRectangle(cornerRadius: 20).strokeBorder(.green.opacity(0.6), lineWidth: 1.5) }
        }
        .task { photo = PhotoCache.shared.image(for: item.exerciseID, entry: context.catalogEntry(item.exerciseID)) }
    }
}
