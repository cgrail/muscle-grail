import SwiftData
import SwiftUI

// Core strings live in Core's catalog, so every one names `bundle: .module`.

public struct SyncStatusView: View {
    private let sync: SyncMonitor

    public init(sync: SyncMonitor = .shared) {
        self.sync = sync
    }

    public var body: some View {
        if let error = sync.lastError {
            Label(error, systemImage: "exclamationmark.icloud").foregroundStyle(.red).lineLimit(3)
        } else if sync.syncing {
            Label { Text("Syncing…", bundle: .module) } icon: { Image(systemName: "arrow.triangle.2.circlepath.icloud") }
        } else if sync.waitingToUpload {
            Label { Text("Waiting to upload", bundle: .module) } icon: { Image(systemName: "icloud.and.arrow.up") }
        } else if let date = sync.lastSync {
            Label { Text("Synced \(date, style: .relative) ago", bundle: .module) } icon: { Image(systemName: "checkmark.icloud") }
        } else {
            Label(String(localized: "Not synced yet", bundle: .module), systemImage: "icloud")
        }
    }
}

/// Unfinished workouts, the plan that is next in rotation, then the other plans. Picking a plan starts a workout, once none runs.
public struct WorkoutPicker: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Plan.order) private var plans: [Plan]
    @Query(Workout.unfinished) private var unfinished: [Workout]
    private let onPick: (Workout) -> Void

    public init(onPick: @escaping (Workout) -> Void) {
        self.onPick = onPick
    }

    public var body: some View {
        List {
            let training = context.isTraining
            ForEach(unfinished) { workout in
                Button(String(localized: "Continue \(workout.title)", bundle: .module), systemImage: "play.fill") { onPick(workout) }
            }
            if training {
                Text("Finish the running workout to start another.", bundle: .module).foregroundStyle(.secondary)
            }
            let next = nextPlan(plans)
            if let next {
                Section { start(next).disabled(training) } header: { Text("Next up", bundle: .module) }
            }
            Section {
                ForEach(plans.filter { $0 != next }) { start($0).disabled(training) }
                if plans.isEmpty {
                    #if os(macOS)
                    Text("No plans yet. Create one under Plans.", bundle: .module).foregroundStyle(.secondary)
                    #else
                    Text("No plans yet. Create one on your Mac.", bundle: .module).foregroundStyle(.secondary)
                    #endif
                }
            } footer: {
                SyncStatusView()
            }
        }
        .navigationTitle(Text("Train", bundle: .module))
        .task(id: plans.count) { await PhotoCache.shared.download(plans.flatMap { $0.trainedItems.map(\.exerciseID) }) }
    }

    private func start(_ plan: Plan) -> some View {
        Button { onPick(context.startWorkout(plan)) } label: {
            VStack(alignment: .leading) {
                Text(plan.title)
                Group {
                    if let focus = plan.focus { Text(verbatim: focus) }
                    if let last = plan.lastDone {
                        Text("Last done \(last, format: .relative(presentation: .named))", bundle: .module)
                    } else {
                        Text("Not done yet", bundle: .module)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// One exercise of a running workout: adjust reps and weight, log a set or all the rest in one tap, swipe a logged set to delete it (right-click on the Mac).
public struct ExerciseSection: View {
    @Environment(\.modelContext) private var context
    private let item: PlanItem
    private let workout: Workout
    @State private var reps = 0
    @State private var weight = 0.0
    @State private var prefilled = false
    @State private var photo: CGImage?

    public init(item: PlanItem, workout: Workout) {
        self.item = item
        self.workout = workout
    }

    public var body: some View {
        let done = workout.sets(of: item.exerciseID)
        let unit = context.weightUnit(of: item.exerciseID)
        Section {
            if let photo {
                Image(decorative: photo, scale: 1).resizable().scaledToFit().frame(maxHeight: 90)
            }
            Stepper(String(localized: "\(reps) reps", bundle: .module), value: $reps, in: 0...200)
            WeightStepper(kg: $weight, exerciseID: item.exerciseID)
            Button(String(localized: "Log set \(done.count + 1) of \(item.targetSets)", bundle: .module), systemImage: "checkmark") {
                context.log(item.exerciseID, reps: reps, weightKg: weight, in: workout)
            }
            if item.targetSets - done.count > 1 {
                let remaining = item.targetSets - done.count
                Button(String(localized: "Log \(remaining) × \(reps) at \(unit.format(weight))", bundle: .module), systemImage: "checkmark.circle") {
                    context.logRemaining(of: item, in: workout, reps: reps, weightKg: weight)
                }
            }
            ForEach(done) { set in
                let delete = Button(String(localized: "Delete", bundle: .module), systemImage: "trash", role: .destructive) { context.undo(set) }
                Text(verbatim: "\(set.reps) × \(unit.format(set.weightKg))")
                    .swipeActions { delete }
                    #if os(macOS)
                    .contextMenu { delete } // a mouse can't swipe
                    #endif
            }
        } header: {
            ExerciseName(item.exerciseID)
        }
        .onAppear {
            guard !prefilled else { return }
            prefilled = true
            (reps, weight) = context.nextSet(for: item, in: workout)
        }
        .task { photo = PhotoCache.shared.image(for: item.exerciseID, entry: context.catalogEntry(item.exerciseID)) }
    }
}

/// One exercise in the workout list, as GymBook shows it: tick off the next set as prefilled, or open it for the details.
public struct ExerciseRow: View {
    @Environment(\.modelContext) private var context
    private let item: PlanItem
    private let workout: Workout
    @State private var photo: CGImage?

    public init(item: PlanItem, workout: Workout) {
        self.item = item
        self.workout = workout
    }

    public var body: some View {
        let done = workout.sets(of: item.exerciseID).count
        let next = context.nextSet(for: item, in: workout)
        HStack {
            Group {
                if let photo {
                    Image(decorative: photo, scale: 1).resizable().scaledToFill()
                } else {
                    Image(systemName: "dumbbell").foregroundStyle(.secondary)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(.rect(cornerRadius: 8))
            .accessibilityHidden(true)
            VStack(alignment: .leading) {
                ExerciseName(item.exerciseID)
                Group {
                    if next.weightKg > 0 {
                        Text("\(done)/\(item.targetSets) sets · \(next.reps) reps · \(context.weightUnit(of: item.exerciseID).format(next.weightKg))", bundle: .module)
                    } else {
                        Text("\(done)/\(item.targetSets) sets · \(next.reps) reps", bundle: .module)
                    }
                }
                .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if done >= item.targetSets {
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green).accessibilityLabel(Text("Done", bundle: .module))
            } else {
                Button(String(localized: "Log set", bundle: .module), systemImage: "checkmark.circle") { context.tick(item, in: workout) }
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .buttonStyle(.borderless) // in a row that opens the details, only this button logs
            }
        }
        .task { photo = PhotoCache.shared.image(for: item.exerciseID, entry: context.catalogEntry(item.exerciseID)) }
    }
}

/// An exercise's name, kept current as its catalog entry changes or arrives.
public struct ExerciseName: View {
    @Query private var entries: [CatalogEntry]
    private let id: String

    public init(_ id: String) {
        self.id = id
        _entries = Query(filter: #Predicate { $0.id == id })
    }

    public var body: some View {
        Text(verbatim: exerciseName(id, entry: entries.first))
    }
}

/// A weight to step through the gym's real weights, or to type, in the exercise's unit, kept current as it changes.
public struct WeightStepper: View {
    @Query private var entries: [CatalogEntry]
    @Binding private var kg: Double
    private let exerciseID: String

    public init(kg: Binding<Double>, exerciseID: String) {
        _kg = kg
        self.exerciseID = exerciseID
        _entries = Query(filter: #Predicate { $0.id == exerciseID })
    }

    public var body: some View {
        let unit = entries.first?.weightUnit ?? .kg
        Stepper {
            #if os(watchOS) // the watch steps with its crown
            Text(verbatim: unit.format(kg))
            #else
            WeightField(kg: $kg, unit: unit)
            #endif
        } onIncrement: {
            kg = Weights.next(after: kg, for: exerciseID, in: unit)
        } onDecrement: {
            kg = Weights.previous(before: kg, for: exerciseID, in: unit)
        }
    }
}

#if !os(watchOS)
/// A weight to type, beside the stepper. Every edit that reads as a weight applies at once: a decimal pad has no
/// return key to commit with, and a set logged mid-edit must get the typed weight.
struct WeightField: View {
    @Binding private var kg: Double
    private let unit: WeightUnit
    @State private var text: String

    init(kg: Binding<Double>, unit: WeightUnit) {
        (_kg, self.unit) = (kg, unit)
        _text = State(initialValue: unit.number(kg.wrappedValue))
    }

    var body: some View {
        HStack(spacing: 4) {
            TextField(String(localized: "Weight", bundle: .module), text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 70)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            Text(verbatim: unit.rawValue)
        }
        .onChange(of: unit) { text = unit.number(kg) }
        .onChange(of: kg) { if Weights.parse(text).map(unit.kg) != kg { text = unit.number(kg) } }
        // A weight shown rounded (49.9 for 49.895) is no edit: only typing changes it.
        .onChange(of: text) { if text != unit.number(kg), let typed = Weights.parse(text).map(unit.kg), typed != kg { kg = typed } }
    }
}
#endif
