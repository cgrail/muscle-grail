import Core
import SwiftUI

#if os(macOS)
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
            VStack(alignment: .leading, spacing: 12) {
                TargetsEditor(sets: sets, reps: reps) { sets = $0 } setReps: { reps = $0 }
                Text("Every exercise you add starts with these, on all your devices.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .frame(width: 260)
            .presentationCompactAdaptation(.popover)
        }
        .onChange(of: sets) { NSUbiquitousKeyValueStore.default.set(sets, forKey: defaultSetsKey) }
        .onChange(of: reps) { NSUbiquitousKeyValueStore.default.set(reps, forKey: defaultRepsKey) }
    }
}
#else
/// Settings → New exercises on the iPhone: the sets and reps every new exercise starts with, on a page of their own. Kept
/// like the Mac's, so every device and Claude add exercises with them.
struct TargetDefaultsLink: View {
    @State private var sets = targetDefaults().sets
    @State private var reps = targetDefaults().reps

    var body: some View {
        NavigationLink {
            Form {
                Section {
                    Stepper(value: $sets, in: 1...20) { LabeledContent("Sets", value: sets.formatted()) }
                    Stepper(value: $reps, in: 1...100) { LabeledContent("Reps", value: reps.formatted()) }
                } footer: {
                    Text("Every exercise you add starts with these, on all your devices.")
                }
            }
            .navigationTitle("New exercises")
        } label: {
            LabeledContent("New exercises") {
                HStack(spacing: 4) {
                    Text("\(sets) sets")
                    Text(verbatim: "×")
                    Text("\(reps) reps")
                }
                .monospacedDigit()
            }
        }
        .onChange(of: sets) { NSUbiquitousKeyValueStore.default.set(sets, forKey: defaultSetsKey) }
        .onChange(of: reps) { NSUbiquitousKeyValueStore.default.set(reps, forKey: defaultRepsKey) }
    }
}
#endif
