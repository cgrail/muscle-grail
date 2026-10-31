import Core
import SwiftData
import SwiftUI

/// A set that differs from the prefill: step its weight through the gym's real weights or type it, step its reps, then
/// log it. The next set prefills from it (`nextSet`), so a heavier set 1 carries over to sets 2 and 3.
struct AdjustSetView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    private let exerciseID: String
    private let number: Int
    private let onLog: (Int, Double) -> Void
    @State private var reps: Int
    @State private var weightKg: Double

    init(exerciseID: String, number: Int, reps: Int, weightKg: Double, onLog: @escaping (Int, Double) -> Void) {
        (self.exerciseID, self.number, self.onLog) = (exerciseID, number, onLog)
        _reps = State(initialValue: reps)
        _weightKg = State(initialValue: weightKg)
    }

    var body: some View {
        let unit = context.weightUnit(of: exerciseID)
        let lighter = Weights.previous(before: weightKg, for: exerciseID, in: unit)
        let heavier = Weights.next(after: weightKg, for: exerciseID, in: unit)
        ScrollView {
            VStack(spacing: 16) {
                StepCard("Weight", down: unit.format(weightKg - lighter), up: unit.format(heavier - weightKg)) {
                    WeightField(kg: $weightKg, unit: unit)
                } onDown: { weightKg = lighter } onUp: { weightKg = heavier }
                .tint(.cyan)
                StepCard("Reps", down: "1", up: "1") {
                    Text(verbatim: "\(reps)").font(.title.bold().monospacedDigit()).foregroundStyle(.tint)
                } onDown: { reps = max(reps - 1, 0) } onUp: { reps = min(reps + 1, 200) }
                .tint(.orange)
                Button {
                    dismiss()
                    onLog(reps, weightKg)
                } label: {
                    Label("Log set \(number)", systemImage: "checkmark").font(.headline).foregroundStyle(.black).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.green)
            }
            .padding()
        }
        .navigationTitle(Text("Set \(number)"))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
}

/// A value with big buttons to step it down and up, each saying by how much: easy to hit between sets.
private struct StepCard<Value: View>: View {
    private let title: LocalizedStringKey
    private let down: String
    private let up: String
    private let value: Value
    private let onDown: () -> Void
    private let onUp: () -> Void

    init(_ title: LocalizedStringKey, down: String, up: String, @ViewBuilder value: () -> Value,
         onDown: @escaping () -> Void, onUp: @escaping () -> Void) {
        (self.title, self.down, self.up, self.value, self.onDown, self.onUp) = (title, down, up, value(), onDown, onUp)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(title).font(.headline).foregroundStyle(.secondary)
                Spacer()
                value
            }
            HStack(spacing: 12) {
                Button(action: onDown) { Label(down, systemImage: "minus").frame(maxWidth: .infinity) }
                Button(action: onUp) { Label(up, systemImage: "plus").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .font(.headline.monospacedDigit())
        }
        .padding()
        .background(.fill.tertiary, in: .rect(cornerRadius: 20))
    }
}
