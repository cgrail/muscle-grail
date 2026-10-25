import Core
import SwiftUI

/// The last year day by day in one grid: gym days, and on the iPhone whether the daily step and walking goals were
/// reached. A selected day shows its workouts, steps and kilometers.
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
        #else
        let (stepGoal, kmGoal) = (0.0, 0.0) // the Mac has no Health, so only gym days
        #endif
        let others = healthOnly(health, besides: workouts)
        Section {
            ActivityGrid(weeks: activityWeeks(gym: gymSessions(workouts, health: health), steps: steps, km: km,
                                              stepGoal: stepGoal, kmGoal: kmGoal, weeks: 53), selected: $selected)
            legend
            VStack(alignment: .leading, spacing: 8) {
                dayPicker
                ForEach(trained(workouts, on: selected)) { WorkoutSummary(workout: $0) }
                let elsewhere = others.filter { Calendar.current.isDate($0, inSameDayAs: selected) }.count
                if elsewhere > 0 { Text("\(elsewhere) workouts from other apps") }
                if trained(workouts, on: selected).isEmpty, elsewhere == 0 { Text("No gym workout").foregroundStyle(.secondary) }
                #if os(iOS)
                let (daySteps, dayKm) = (steps[selected] ?? 0, km[selected] ?? 0)
                Text(stepGoal > 0 ? "\(daySteps.formatted(.number.precision(.fractionLength(0)))) of \(stepGoal.formatted()) steps"
                                  : "\(daySteps.formatted(.number.precision(.fractionLength(0)))) steps")
                Text(kmGoal > 0 ? "\(dayKm.formatted(.number.precision(.fractionLength(1)))) of \(kmGoal.formatted()) km walked"
                                : "\(dayKm.formatted(.number.precision(.fractionLength(1)))) km walked")
                #endif
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
        }
        #endif
    }

    private var legend: some View {
        HStack(spacing: 12) {
            key(3, "Gym")
            #if os(iOS)
            key(2, "Goal reached")
            key(1, "Short of goal")
            #endif
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func key(_ level: Int, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(ActivityGrid.color(level)).frame(width: 11, height: 11)
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
