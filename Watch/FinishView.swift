import Core
import SwiftUI

/// The workout before it ends: the volume lifted, how long it ran, and each exercise's sets against its target.
/// Done ends it and saves it to Health; closing the sheet goes back to the workout.
struct FinishView: View {
    let workout: Workout
    let onDone: () -> Void

    var body: some View {
        List {
            VStack(spacing: 4) {
                Image(systemName: "trophy.fill").font(.title2).foregroundStyle(.green)
                Text("Workout complete!").font(.headline)
                Text(workout.title).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            Section {
                LabeledContent("Volume") {
                    Text(verbatim: "\(workout.volumeKg.formatted(.number.precision(.fractionLength(0)))) kg").foregroundStyle(.cyan)
                }
                LabeledContent("Duration") {
                    Text(Duration.seconds(Date.now.timeIntervalSince(workout.start))
                        .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                        .foregroundStyle(.orange)
                }
            }
            Section {
                ForEach(workout.plan?.trainedItems ?? []) { item in
                    let done = workout.sets(of: item.exerciseID).count
                    LabeledContent {
                        Text(verbatim: "\(done)/\(item.targetSets)").monospacedDigit().foregroundStyle(done >= item.targetSets ? Color.green : Color.secondary)
                    } label: {
                        ExerciseName(item.exerciseID)
                    }
                }
            }
            Button("Done & save to Health", action: onDone)
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .listRowBackground(Color.clear)
        }
    }
}
