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
        } else if let date = sync.lastSync {
            Label { Text("Synced \(date, style: .relative) ago", bundle: .module) } icon: { Image(systemName: "checkmark.icloud") }
        } else {
            Label(String(localized: "Not synced yet", bundle: .module), systemImage: "icloud")
        }
    }
}

/// Unfinished workouts and plans. Picking a plan starts a workout.
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
            ForEach(unfinished) { workout in
                Button(String(localized: "Continue \(workout.title)", bundle: .module), systemImage: "play.fill") { onPick(workout) }
            }
            Section {
                ForEach(plans) { plan in
                    Button(plan.title) { onPick(context.startWorkout(plan)) }
                }
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

    public init(item: PlanItem, workout: Workout) {
        self.item = item
        self.workout = workout
    }

    public var body: some View {
        let done = workout.sets(of: item.exerciseID)
        Section {
            Stepper(String(localized: "\(reps) reps", bundle: .module), value: $reps, in: 0...200)
            Stepper(String(localized: "\(weight.formatted()) kg", bundle: .module), value: $weight, in: 0...1000, step: 2.5)
            Button(String(localized: "Log set \(done.count + 1) of \(item.targetSets)", bundle: .module), systemImage: "checkmark") {
                context.log(item.exerciseID, reps: reps, weightKg: weight, in: workout)
            }
            if item.targetSets - done.count > 1 {
                let remaining = item.targetSets - done.count
                Button(String(localized: "Log \(remaining) × \(reps) at \(weight.formatted()) kg", bundle: .module), systemImage: "checkmark.circle") {
                    context.logRemaining(of: item, in: workout, reps: reps, weightKg: weight)
                }
            }
            ForEach(done) { set in
                let delete = Button(String(localized: "Delete", bundle: .module), systemImage: "trash", role: .destructive) { context.undo(set) }
                Text(verbatim: "\(set.reps) × \(set.weightKg.formatted()) kg")
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
