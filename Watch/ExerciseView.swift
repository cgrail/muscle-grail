import Core
import SwiftData
import SwiftUI

/// One exercise of the running workout: its next set as prefilled, logged in one tap, adjusted first, or logged with all
/// the remaining sets at once. Below, the sets done, swiped to delete, and how to do it. `onDone` runs once its target
/// sets are logged, so three taps on Log set log the exercise and go back to the list.
struct ExerciseView: View {
    @Environment(\.modelContext) private var context
    @Query private var entries: [CatalogEntry]
    private let item: PlanItem
    private let workout: Workout
    private let onDone: () -> Void
    @State private var adjusting = false
    @State private var photo: CGImage?

    init(item: PlanItem, workout: Workout, onDone: @escaping () -> Void) {
        (self.item, self.workout, self.onDone) = (item, workout, onDone)
        let id = item.exerciseID
        _entries = Query(filter: #Predicate { $0.id == id })
    }

    var body: some View {
        let done = workout.sets(of: item.exerciseID)
        let next = context.nextSet(for: item, in: workout)
        let unit = context.weightUnit(of: item.exerciseID)
        List {
            Section {
                VStack(spacing: 2) {
                    ExerciseName(item.exerciseID).font(.headline).foregroundStyle(.orange)
                    Text("Set \(done.count + 1) of \(item.targetSets)").foregroundStyle(.cyan)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: "\(next.reps)").font(.title2.bold())
                    Text("reps").foregroundStyle(.secondary)
                    if next.weightKg > 0 {
                        Text(verbatim: "@ \(unit.number(next.weightKg))").font(.title2.bold())
                        Text(verbatim: unit.rawValue).foregroundStyle(.secondary)
                    }
                }
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                Button("Log set \(done.count + 1)", systemImage: "checkmark") { log(reps: next.reps, weightKg: next.weightKg) }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .listRowBackground(Color.clear)
                HStack {
                    Button("Adjust", systemImage: "slider.horizontal.3") { adjusting = true }
                    if item.targetSets - done.count > 1 {
                        Button("Log all", systemImage: "checkmark.circle") {
                            context.logRemaining(of: item, in: workout, reps: next.reps, weightKg: next.weightKg)
                            onDone()
                        }
                        .foregroundStyle(.yellow)
                    }
                }
                .buttonStyle(.bordered)
                .font(.footnote)
                .listRowBackground(Color.clear)
            }
            if !done.isEmpty {
                Section("Done") {
                    ForEach(done) { set in
                        Text(verbatim: "\(set.reps) × \(unit.format(set.weightKg))")
                            .swipeActions { Button("Delete", systemImage: "trash", role: .destructive) { context.undo(set) } }
                    }
                }
            }
            let steps = instructions(item.exerciseID, entry: entries.first)
            if photo != nil || !steps.isEmpty {
                Section("How to") {
                    if let photo {
                        Image(decorative: photo, scale: 1).resizable().scaledToFit().frame(maxHeight: 90)
                    }
                    ForEach(steps, id: \.self) { Text(verbatim: $0).font(.footnote) }
                }
            }
        }
        .sheet(isPresented: $adjusting) {
            NavigationStack {
                AdjustSetView(exerciseID: item.exerciseID, number: done.count + 1, reps: next.reps, weightKg: next.weightKg) {
                    log(reps: $0, weightKg: $1)
                }
            }
        }
        .task { photo = PhotoCache.shared.image(for: item.exerciseID, entry: entries.first) }
    }

    private func log(reps: Int, weightKg: Double) {
        context.log(item.exerciseID, reps: reps, weightKg: weightKg, in: workout)
        if workout.sets(of: item.exerciseID).count >= item.targetSets { onDone() }
    }
}
