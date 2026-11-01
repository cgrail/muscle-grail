#if os(macOS)
import Core
import SwiftUI

/// The sets and reps every new exercise starts with, under the Mac's sidebar, to change in a popover. They're kept in
/// iCloud's key-value store, so the iPhone and Claude add exercises with them too.
struct TargetDefaultsPanel: View {
    @State private var sets = targetDefaults().sets
    @State private var reps = targetDefaults().reps
    @State private var editing = false

    var body: some View {
        Button { editing = true } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("New exercises").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text("\(sets) sets")
                    Text(verbatim: "×")
                    Text("\(reps) reps")
                }
                .font(.headline.monospacedDigit())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $editing) {
            Form {
                Stepper("\(sets) sets", value: $sets, in: 1...20)
                Stepper("\(reps) reps", value: $reps, in: 1...100)
                Text("Every exercise you add starts with these, on all your devices.").font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .frame(width: 260)
        }
        .onChange(of: sets) { NSUbiquitousKeyValueStore.default.set(sets, forKey: defaultSetsKey) }
        .onChange(of: reps) { NSUbiquitousKeyValueStore.default.set(reps, forKey: defaultRepsKey) }
    }
}
#endif
