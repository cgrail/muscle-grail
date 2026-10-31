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
            Text(verbatim: unit.format(kg)).font(.title3).minimumScaleFactor(0.5) // the stepper's own font truncates "47.5 kg"
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
/// A weight to type, beside a stepper's buttons. Every edit that reads as a weight applies at once: a decimal pad has no
/// return key to commit with, and a set logged mid-edit must get the typed weight.
public struct WeightField: View {
    @Binding private var kg: Double
    private let unit: WeightUnit
    @State private var text: String

    public init(kg: Binding<Double>, unit: WeightUnit) {
        (_kg, self.unit) = (kg, unit)
        _text = State(initialValue: unit.number(kg.wrappedValue))
    }

    public var body: some View {
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
