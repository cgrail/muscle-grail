import Core
import SwiftData
import SwiftUI

/// The selected day's steps and distance toward the daily goals, its workouts, and the last year day by day, as on the
/// iPhone. Tapping the complication opens it.
struct ActivityView: View {
    @Query(Workout.history) private var workouts: [Workout]
    @State private var selected = Calendar.current.startOfDay(for: .now)
    @State private var health: [(start: Date, id: UUID)] = []
    @State private var steps: [Date: Double] = [:]
    @State private var km: [Date: Double] = [:]

    var body: some View {
        let goals = dailyGoals()
        let (daySteps, dayKm) = (steps[selected] ?? 0, km[selected] ?? 0)
        List {
            Section {
                Label("\(daySteps.formatted(.number.precision(.fractionLength(0)))) steps", systemImage: "shoeprints.fill")
                Label("\(dayKm.formatted(.number.precision(.fractionLength(1)))) km", systemImage: "figure.walk")
                if let progress = dayProgress(steps: daySteps, km: dayKm, stepGoal: goals.steps, kmGoal: goals.km) {
                    ProgressView(value: progress)
                }
                ForEach(trained(workouts, on: selected)) { Label($0.title, systemImage: "dumbbell.fill").foregroundStyle(.red) }
            } header: {
                Text(selected, format: .dateTime.weekday(.wide).day().month())
            }
            ActivityGrid(weeks: activityWeeks(gym: gymSessions(workouts, health: health), steps: steps, km: km,
                                              stepGoal: goals.steps, kmGoal: goals.km, weeks: 53), selected: $selected)
        }
        .navigationTitle("Activity")
        .task {
            async let health = Health.strengthWorkouts(since: .now.addingTimeInterval(-371 * 24 * 3600))
            async let steps = Health.daily(.stepCount, unit: .count(), days: 371)
            async let km = Health.daily(.distanceWalkingRunning, unit: .meterUnit(with: .kilo), days: 371)
            (self.health, self.steps, self.km) = await (health, steps, km)
        }
    }
}
