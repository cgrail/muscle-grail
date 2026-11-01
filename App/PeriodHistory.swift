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

/// A week, month, quarter or year to open in the history, from a bar of the statistics chart.
struct OpenedPeriod: Hashable {
    let period: Period
    let interval: DateInterval
}

/// A year, quarter, month or week: how often each plan was trained, then its months or its workouts.
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
            if period == .year || period == .quarter {
                Section("Months") { PeriodLinks(workouts: workouts, period: .month) }
            } else {
                Section("Workouts") { ForEach(workouts) { WorkoutRow(workout: $0) } }
            }
        }
        .navigationTitle(title)
    }

    private var title: String {
        let days = interval.start..<interval.end.addingTimeInterval(-1) // the end is where the next period starts
        return switch period {
        case .year: interval.start.formatted(.dateTime.year())
        case .quarter: days.formatted(.interval.month(.wide).year())
        case .month: interval.start.formatted(.dateTime.month(.wide).year())
        case .week: days.formatted(.interval.day().month().year())
        }
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
