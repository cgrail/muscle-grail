import Core
import SwiftUI

/// The last year day by day in one grid: gym days, and on the iPhone whether the daily step and walking goals were
/// reached. A selected day shows its workouts, steps and kilometers (on the Mac, as the iPhone last copied them).
struct ActivitySection: View {
    let workouts: [Workout]
    @State private var selected = Calendar.current.startOfDay(for: .now)
    @State private var health: [(start: Date, id: UUID)] = []
    @State private var steps: [Date: Double] = [:]
    @State private var km: [Date: Double] = [:]
    #if os(iOS)
    @State private var goals = Goals()
    @State private var editingGoals = false
    #endif

    var body: some View {
        #if os(iOS)
        let (stepGoal, kmGoal) = (goals.steps, goals.km)
        let weeks = activityWeeks(gym: gymSessions(workouts, health: health), steps: steps, km: km, stepGoal: stepGoal, kmGoal: kmGoal, weeks: 53)
        #else
        let (stepGoal, kmGoal) = (0.0, 0.0) // the Mac has no Health: only gym days in the grid, the iPhone's steps and km below
        let weeks = activityWeeks(gym: gymSessions(workouts, health: health), weeks: 53)
        #endif
        let others = healthOnly(health, besides: workouts)
        Section {
            ActivityGrid(weeks: weeks, selected: $selected)
            legend
            VStack(alignment: .leading, spacing: 8) {
                dayPicker
                ForEach(trained(workouts, on: selected)) { WorkoutSummary(workout: $0) }
                let elsewhere = others.filter { Calendar.current.isDate($0, inSameDayAs: selected) }.count
                if elsewhere > 0 { Text("\(elsewhere) workouts from other apps") }
                if trained(workouts, on: selected).isEmpty, elsewhere == 0 { Text("No gym workout").foregroundStyle(.secondary) }
                let (daySteps, dayKm) = (steps[selected] ?? 0, km[selected] ?? 0)
                Text(stepGoal > 0 ? "\(daySteps.formatted(.number.precision(.fractionLength(0)))) of \(stepGoal.formatted()) steps"
                                  : "\(daySteps.formatted(.number.precision(.fractionLength(0)))) steps")
                Text(kmGoal > 0 ? "\(dayKm.formatted(.number.precision(.fractionLength(1)))) of \(kmGoal.formatted()) km walked"
                                : "\(dayKm.formatted(.number.precision(.fractionLength(1)))) km walked")
            }
        } header: {
            HStack {
                Text("Activity")
                #if os(iOS)
                Spacer()
                Button("Goals") { editingGoals = true }
                #endif
            }
        }
        #if os(iOS)
        .sheet(isPresented: $editingGoals) { GoalsEditor(goals: goals) }
        .task {
            async let health = Health.strengthWorkouts(since: .now.addingTimeInterval(-371 * 24 * 3600))
            async let steps = Health.daily(.stepCount, unit: .count(), days: 371)
            async let km = Health.daily(.distanceWalkingRunning, unit: .meterUnit(with: .kilo), days: 371)
            (self.health, self.steps, self.km) = await (health, steps, km)
            saveDaily(steps: self.steps, km: self.km)
        }
        #else
        .onAppear {
            NSUbiquitousKeyValueStore.default.synchronize()
            (steps, km) = savedDaily()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification).receive(on: DispatchQueue.main)) { _ in
            (steps, km) = savedDaily()
        }
        #endif
    }

    private var legend: some View {
        HStack(spacing: 12) {
            key([5], "Gym")
            #if os(iOS)
            key([1, 2, 3], "Short of goal")
            key([4], "Goal reached")
            #endif
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func key(_ levels: [Int], _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(levels, id: \.self) { RoundedRectangle(cornerRadius: 2).fill(ActivityGrid.color($0)).frame(width: 11, height: 11) }
            }
            Text(title)
        }
    }

    /// The selected day, a day back or ahead: the arrows are easier to hit than a square.
    private var dayPicker: some View {
        HStack {
            Button("Previous day", systemImage: "chevron.left") { move(-1) }
            Spacer()
            Text(selected, format: .dateTime.weekday(.wide).day().month()).font(.headline)
            Spacer()
            Button("Next day", systemImage: "chevron.right") { move(1) }.disabled(Calendar.current.isDateInToday(selected))
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }

    private func move(_ days: Int) {
        selected = Calendar.current.date(byAdding: .day, value: days, to: selected)!
    }
}
