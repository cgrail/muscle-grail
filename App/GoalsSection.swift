#if os(iOS)
import Core
import SwiftUI

/// Daily goals, in iCloud's key-value store so every device has them. 0 means no goal.
@MainActor @Observable final class Goals {
    private let store = NSUbiquitousKeyValueStore.default
    var steps: Double { didSet { store.set(steps, forKey: "goalSteps") } }
    var km: Double { didSet { store.set(km, forKey: "goalKm") } }

    init() {
        steps = store.object(forKey: "goalSteps") == nil ? 10_000 : store.double(forKey: "goalSteps")
        km = store.double(forKey: "goalKm")
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.load() }
        }
        store.synchronize()
    }

    private func load() {
        steps = store.object(forKey: "goalSteps") == nil ? 10_000 : store.double(forKey: "goalSteps")
        km = store.double(forKey: "goalKm")
    }
}

/// Today's progress toward each daily goal, and every day of the last year as GitHub shows contributions.
struct GoalsSection: View {
    @State private var goals = Goals()
    @State private var steps: [Date: Double] = [:]
    @State private var km: [Date: Double] = [:]
    @State private var editing = false

    var body: some View {
        let today = Calendar.current.startOfDay(for: .now)
        Section {
            if goals.steps > 0 {
                Text("\((steps[today] ?? 0).formatted(.number.precision(.fractionLength(0)))) of \(goals.steps.formatted()) steps")
                ActivityGrid(weeks: goalWeeks(steps, goal: goals.steps, weeks: 53), color: .orange)
            }
            if goals.km > 0 {
                Text("\((km[today] ?? 0).formatted(.number.precision(.fractionLength(1)))) of \(goals.km.formatted()) km walked")
                ActivityGrid(weeks: goalWeeks(km, goal: goals.km, weeks: 53), color: .blue)
            }
            if goals.steps == 0, goals.km == 0 {
                Text("Set a daily goal for steps or walking distance.").foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Daily goals")
                Spacer()
                Button("Edit") { editing = true }
            }
        }
        .sheet(isPresented: $editing) { GoalsEditor(goals: goals) }
        .task {
            async let steps = Health.daily(.stepCount, unit: .count(), days: 371)
            async let km = Health.daily(.distanceWalkingRunning, unit: .meterUnit(with: .kilo), days: 371)
            (self.steps, self.km) = await (steps, km)
        }
    }
}

private struct GoalsEditor: View {
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
