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

/// A running workout on top, then the plans in `trainingOrder`: the one done longest ago is next up, the one done last comes last.
/// Picking a plan opens it to train, once no workout runs; its workout starts with the first set logged.
public struct WorkoutPicker: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Plan.order) private var plans: [Plan]
    @Query(Workout.unfinished) private var unfinished: [Workout]
    private let onContinue: (Workout) -> Void
    private let onStart: (Plan) -> Void

    public init(onContinue: @escaping (Workout) -> Void, onStart: @escaping (Plan) -> Void) {
        (self.onContinue, self.onStart) = (onContinue, onStart)
    }

    public var body: some View {
        List {
            let training = context.isTraining
            if training {
                Section {
                    ForEach(unfinished) { running($0) }
                } header: {
                    Text("Continue", bundle: .module)
                } footer: {
                    Text("Finish the running workout to start another.", bundle: .module)
                }
            }
            let order = trainingOrder(plans)
            if let next = order.first {
                Section { start(next).disabled(training) } header: { Text("Next up", bundle: .module) }
            }
            Section {
                ForEach(order.dropFirst()) { start($0).disabled(training) }
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
        .navigationTitle(Text("Training", bundle: .module))
        .task(id: plans.count) { await PhotoCache.shared.download(plans.flatMap { $0.trainedItems.map(\.exerciseID) }) }
    }

    private func running(_ workout: Workout) -> some View {
        Button { onContinue(workout) } label: {
            HStack {
                if let plan = workout.plan { PlanLabel(plan, among: plans) } else { Text(workout.title).font(.headline) }
                #if !os(watchOS) // no room beside the name
                Spacer()
                Image(systemName: "play.circle.fill").font(.largeTitle).foregroundStyle(.tint)
                #endif
            }
        }
        .accessibilityLabel(String(localized: "Continue \(workout.title)", bundle: .module))
    }

    private func start(_ plan: Plan) -> some View {
        Button { onStart(plan) } label: { PlanLabel(plan, among: plans) }
    }
}

/// A plan as the lists show it: its picture, its name, what it trains, the exercises no other of `plans` has,
/// and when and how often it was done.
public struct PlanLabel: View {
    @Environment(\.modelContext) private var context
    private let plan: Plan
    private let plans: [Plan]

    public init(_ plan: Plan, among plans: [Plan]) {
        (self.plan, self.plans) = (plan, plans)
    }

    public var body: some View {
        HStack(spacing: 12) {
            #if os(watchOS)
            PlanPicture(plan, size: 32)
            #else
            PlanPicture(plan, size: 48)
            #endif
            VStack(alignment: .leading) {
                Text(plan.title).font(.headline)
                Group {
                    if let focus = plan.focus { Text(verbatim: focus) }
                    let special = specialExercises(of: plan, among: plans).map { context.exerciseName($0) }
                    if !special.isEmpty { Text(verbatim: special.joined(separator: ", ")).lineLimit(1) }
                    Text(verbatim: plan.lastDoneText)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// A plan's picture: the drawing of its character, the one chosen or for its name or what it trains, else a lifter,
/// on a tile in the plan's color.
public struct PlanPicture: View {
    private let plan: Plan
    private let size: Double

    public init(_ plan: Plan, size: Double) {
        (self.plan, self.size) = (plan, size)
    }

    public var body: some View {
        CharacterPicture(plan.character, color: plan.color, size: size)
    }
}

/// A character's drawing, else a lifter, on a tile in `color`.
public struct CharacterPicture: View {
    private let character: FunnyCharacter?
    private let color: Color
    private let size: Double

    public init(_ character: FunnyCharacter?, color: Color, size: Double) {
        (self.character, self.color, self.size) = (character, color, size)
    }

    public var body: some View {
        Group {
            if let image = character?.picture.flatMap({ try? Data(contentsOf: $0) }).flatMap(Photo.image) {
                Image(decorative: image, scale: 1).resizable().scaledToFit().padding(size * 0.06)
            } else {
                Image(systemName: "figure.strengthtraining.traditional").font(.system(size: size * 0.5)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .background(color.gradient, in: .rect(cornerRadius: size / 4))
        .accessibilityHidden(true) // the name beside it says it
    }
}

public extension Plan {
    /// The plan's color, from its place in the list, so plans side by side differ.
    var color: Color { [Color.orange, .pink, .purple, .indigo, .blue, .teal, .green, .mint, .red][abs(order) % 9] }
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
