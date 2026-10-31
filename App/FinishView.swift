import Core
import SwiftUI

/// The workout before it ends: the volume lifted, the sets done against the plan, how long it ran, and each exercise's
/// sets. Finish ends it, on the iPhone saving it to Health; Cancel goes back to the workout.
struct FinishView: View {
    @Environment(\.dismiss) private var dismiss
    let workout: Workout
    let onFinish: () -> Void

    var body: some View {
        let items = workout.plan?.trainedItems ?? []
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.green)
                        .frame(width: 72, height: 72)
                        .background(.green.opacity(0.15), in: .circle)
                    Text(workout.isComplete ? "Workout complete!" : "Workout summary").font(.title2.bold())
                    Text(workout.title).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    tile("Volume", "\(workout.volumeKg.formatted(.number.precision(.fractionLength(0)))) kg", .cyan)
                    tile("Sets", "\(workout.sets?.count ?? 0)/\(items.map(\.targetSets).reduce(0, +))", .green)
                    tile("Duration", Duration.seconds(Date.now.timeIntervalSince(workout.start))
                        .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)), .orange)
                }
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        let done = workout.sets(of: item.exerciseID).count
                        HStack {
                            ExerciseName(item.exerciseID)
                            Spacer()
                            Text(verbatim: "\(done)/\(item.targetSets)")
                                .monospacedDigit()
                                .foregroundStyle(done >= item.targetSets ? Color.green : Color.secondary)
                        }
                        .padding(.vertical, 10)
                        if item != items.last { Divider() }
                    }
                }
                .padding(.horizontal)
                .background(.fill.tertiary, in: .rect(cornerRadius: 20))
                #if os(iOS) // the Mac has no HealthKit
                Label {
                    Text("Finishing saves this workout to Apple Health.")
                } icon: {
                    Image(systemName: "heart.fill").foregroundStyle(.red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.fill.tertiary, in: .rect(cornerRadius: 20))
                #endif
                Button(action: onFinish) {
                    Label("Finish workout", systemImage: "flag.checkered").font(.headline).foregroundStyle(.black).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.green)
            }
            .padding()
        }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }

    private func tile(_ title: LocalizedStringKey, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption.bold()).textCase(.uppercase).foregroundStyle(.secondary)
            Text(verbatim: value).font(.title3.bold().monospacedDigit()).foregroundStyle(color)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.fill.tertiary, in: .rect(cornerRadius: 20))
    }
}
