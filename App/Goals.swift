#if os(iOS)
import Core
import SwiftUI

/// Daily goals, in iCloud's key-value store so every device has them. 0 means no goal.
@MainActor @Observable final class Goals {
    private let store = NSUbiquitousKeyValueStore.default
    var steps: Double { didSet { store.set(steps, forKey: "goalSteps") } }
    var km: Double { didSet { store.set(km, forKey: "goalKm") } }

    init() {
        (steps, km) = dailyGoals(in: store)
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.load() }
        }
        store.synchronize()
    }

    private func load() {
        (steps, km) = dailyGoals(in: store)
    }
}

/// Sets the daily goals: steps and kilometers walked, each off at 0.
struct GoalsEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var goals: Goals

    var body: some View {
        NavigationStack {
            Form {
                Stepper(value: $goals.steps, in: 0...50_000, step: 1_000) {
                    LabeledContent("Steps per day", value: goals.steps == 0 ? String(localized: "Off") : goals.steps.formatted())
                }
                Stepper(value: $goals.km, in: 0...50, step: 0.5) {
                    LabeledContent("Kilometers walked per day", value: goals.km == 0 ? String(localized: "Off") : goals.km.formatted())
                }
            }
            .navigationTitle("Daily goals")
            .toolbar { Button("Done") { dismiss() } }
        }
        .presentationDetents([.medium])
    }
}
#endif
