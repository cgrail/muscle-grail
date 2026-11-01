import Core
import SwiftData
import SwiftUI

/// An exercise's sets and reps as text, "3 × 10". A click opens them to type or step.
struct TargetsButton: View {
    @Environment(\.modelContext) private var context
    let item: PlanItem
    @State private var editing = false

    var body: some View {
        Button { editing = true } label: {
            HStack(spacing: 4) {
                Text(verbatim: "\(item.targetSets)").fontWeight(.semibold)
                Text(verbatim: "× \(item.targetReps)").foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .contentShape(.rect)
        }
        #if os(iOS)
        .buttonStyle(.bordered)
        #else
        .buttonStyle(.plain)
        #endif
        .help("Click to change the sets and reps.")
        .popover(isPresented: $editing) {
            TargetsEditor(sets: item.targetSets, reps: item.targetReps) { context.setTargets(item, sets: $0) } setReps: { context.setTargets(item, reps: $0) }
                .padding()
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// Sets and reps, each a number to step to, or on the Mac to type.
struct TargetsEditor: View {
    let sets: Int, reps: Int
    let setSets: (Int) -> Void, setReps: (Int) -> Void

    var body: some View {
        Grid(alignment: .leading) {
            GridRow {
                Text("Sets")
                count("Sets", sets, in: 1...20, set: setSets)
            }
            GridRow {
                Text("Reps")
                count("Reps", reps, in: 1...100, set: setReps)
            }
        }
    }

    /// A typed number outside `range` lands on its nearest end.
    private func count(_ title: LocalizedStringKey, _ value: Int, in range: ClosedRange<Int>, set: @escaping (Int) -> Void) -> some View {
        let binding = Binding { value } set: { set(min(max($0, range.lowerBound), range.upperBound)) }
        return Stepper(value: binding, in: range) {
            #if os(iOS) // a number pad has no return key to commit a typed number with
            Text(verbatim: "\(value)").monospacedDigit().frame(minWidth: 44, alignment: .trailing)
            #else
            TextField(title, value: binding, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 44)
            #endif
        }
    }
}
