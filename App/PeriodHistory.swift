import Core
import SwiftData
import SwiftUI

/// One link per year or month with workouts, newest first, with how many were trained in it.
struct PeriodLinks: View {
    let workouts: [Workout]
    let period: Period

    var body: some View {
        ForEach(periods(workouts, per: period), id: \.interval) { group in
            NavigationLink {
                PeriodHistory(period: period, interval: group.interval)
            } label: {
                LabeledContent(group.interval.start.formatted(period == .year ? Date.FormatStyle.dateTime.year() : .dateTime.month(.wide))) {
                    Text(group.count.formatted())
                }
            }
        }
    }
}

/// A year or a month: how often each plan was trained, then the year's months or the month's workouts.
struct PeriodHistory: View {
    let period: Period
    let interval: DateInterval
    @Query private var workouts: [Workout]

    init(period: Period, interval: DateInterval) {
        self.period = period
        self.interval = interval
        _workouts = Query(Workout.history(in: interval))
    }

    var body: some View {
        List {
            Section("By plan") {
                ForEach(timesDone(workouts), id: \.title) { training in
                    LabeledContent(training.title) { Text(verbatim: "\(training.count)×") }
                }
            }
            if period == .year {
                Section("Months") { PeriodLinks(workouts: workouts, period: .month) }
            } else {
                Section("Workouts") { ForEach(workouts) { WorkoutRow(workout: $0) } }
            }
        }
        .navigationTitle(interval.start.formatted(period == .year ? Date.FormatStyle.dateTime.year() : .dateTime.month(.wide).year()))
    }
}

/// A workout's plan and start, opening to its exercises and sets.
struct WorkoutRow: View {
    @Environment(\.modelContext) private var context
    let workout: Workout

    var body: some View {
        NavigationLink {
            List { WorkoutSummary(workout: workout) }
                .navigationTitle(workout.title)
        } label: {
            VStack(alignment: .leading) {
                Text(workout.title).font(.headline)
                Text(workout.start, format: .dateTime.weekday().day().month().hour().minute())
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) { context.deleteWorkout(workout) }
        }
    }
}
