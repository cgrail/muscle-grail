import Core
import SwiftData
import SwiftUI

/// One exercise of the running workout: its sets as dots, the next set as prefilled, logged in one tap, adjusted first,
/// or logged with all the remaining sets at once. Below, the sets logged, swiped to delete (right-click on the Mac), and
/// how to do it. `onDone` runs once its target sets are logged, so logging the last one goes back to the workout.
struct ExerciseView: View {
    @Environment(\.modelContext) private var context
    let item: PlanItem
    let workout: Workout
    let onDone: () -> Void
    @State private var adjusting = false
    @State private var photo: CGImage?

    var body: some View {
        let done = workout.sets(of: item.exerciseID)
        let next = context.nextSet(for: item, in: workout)
        let unit = context.weightUnit(of: item.exerciseID)
        List {
            Section {
                VStack(spacing: 16) {
                    if let photo {
                        Image(decorative: photo, scale: 1).resizable().scaledToFit().frame(maxHeight: 120)
                    }
                    SetDots(done: done.count, target: item.targetSets)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: "\(next.reps)").font(.system(size: 52, weight: .bold, design: .rounded))
                        Text("reps").font(.title3).foregroundStyle(.secondary)
                        if next.weightKg > 0 {
                            Text(verbatim: "@").font(.title.bold()).foregroundStyle(.secondary)
                            Text(verbatim: unit.number(next.weightKg)).font(.system(size: 52, weight: .bold, design: .rounded))
                                .foregroundStyle(.cyan)
                            Text(verbatim: unit.rawValue).font(.title3).foregroundStyle(.secondary)
                        }
                    }
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    if let detail = CatalogExercise.byID[item.exerciseID]?.detail {
                        Text(verbatim: detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            }
            Section {
                VStack(spacing: 12) {
                    Button { log(reps: next.reps, weightKg: next.weightKg) } label: {
                        Label("Log set \(done.count + 1)", systemImage: "checkmark").font(.headline).foregroundStyle(.black).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    HStack(spacing: 12) {
                        Button { adjusting = true } label: {
                            Label("Adjust", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity)
                        }
                        if item.targetSets - done.count > 1 {
                            Button {
                                context.logRemaining(of: item, in: workout, reps: next.reps, weightKg: next.weightKg)
                                onDone()
                            } label: {
                                Label("Log all", systemImage: "checkmark.circle").frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            if !done.isEmpty {
                Section("Logged") {
                    ForEach(done) { set in
                        let delete = Button("Delete", systemImage: "trash", role: .destructive) { context.undo(set) }
                        Label {
                            Text(verbatim: "\(set.reps) × \(unit.format(set.weightKg))").monospacedDigit()
                        } icon: {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                        .swipeActions { delete }
                        #if os(macOS)
                        .contextMenu { delete } // a mouse can't swipe
                        #endif
                    }
                }
            }
            ExerciseGuide(id: item.exerciseID)
        }
        .navigationTitle(context.exerciseName(item.exerciseID))
        .sheet(isPresented: $adjusting) {
            NavigationStack {
                AdjustSetView(exerciseID: item.exerciseID, number: done.count + 1, reps: next.reps, weightKg: next.weightKg) {
                    log(reps: $0, weightKg: $1)
                }
            }
        }
        .task { photo = PhotoCache.shared.image(for: item.exerciseID, entry: context.catalogEntry(item.exerciseID)) }
    }

    private func log(reps: Int, weightKg: Double) {
        context.log(item.exerciseID, reps: reps, weightKg: weightKg, in: workout)
        if workout.sets(of: item.exerciseID).count >= item.targetSets { onDone() }
    }
}

/// An exercise's sets as numbered dots, the done ones filled and the next one outlined. Too many for the width show as a count.
private struct SetDots: View {
    let done: Int
    let target: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                ForEach(1..<max(target, done) + 1, id: \.self) { number in
                    Text(verbatim: "\(number)")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(number <= done ? Color.black : number == done + 1 ? Color.green : Color.secondary)
                        .frame(width: 36, height: 36)
                        .background(number <= done ? Color.green : Color.clear, in: .circle)
                        .overlay { Circle().strokeBorder(number == done + 1 ? Color.green : Color.secondary.opacity(0.4), lineWidth: 2) }
                }
            }
            Text("\(done)/\(target) sets").font(.subheadline.bold().monospacedDigit()).foregroundStyle(.green)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(done)/\(target) sets"))
    }
}
