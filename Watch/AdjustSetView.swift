import Core
import SwiftData
import SwiftUI

/// A set that differs from the prefill: step its weight with the Digital Crown or the stepper, and its reps, then log it.
/// The next set prefills from it (`nextSet`), so a heavier set 1 carries over to sets 2 and 3.
struct AdjustSetView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    private let exerciseID: String
    private let number: Int
    private let onLog: (Int, Double) -> Void
    @State private var reps: Int
    @State private var weightKg: Double
    @State private var crown = 0.0

    init(exerciseID: String, number: Int, reps: Int, weightKg: Double, onLog: @escaping (Int, Double) -> Void) {
        (self.exerciseID, self.number, self.onLog) = (exerciseID, number, onLog)
        _reps = State(initialValue: reps)
        _weightKg = State(initialValue: weightKg)
    }

    var body: some View {
        VStack(spacing: 8) {
            WeightStepper(kg: $weightKg, exerciseID: exerciseID)
                .focusable()
                // Each detent steps to the next real weight, as the stepper does: gloves find the crown easier than its buttons.
                .digitalCrownRotation(detent: $crown, from: -10_000, through: 10_000, by: 1, sensitivity: .low)
                .onChange(of: crown) { old, new in
                    let unit = context.weightUnit(of: exerciseID)
                    weightKg = new > old ? Weights.next(after: weightKg, for: exerciseID, in: unit)
                        : Weights.previous(before: weightKg, for: exerciseID, in: unit)
                }
            Stepper(value: $reps, in: 0...200) { Text("\(reps) reps").font(.title3).minimumScaleFactor(0.5) }
            Button("Log set \(number)", systemImage: "checkmark") {
                dismiss()
                onLog(reps, weightKg)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .navigationTitle(Text("Set \(number)"))
    }
}
