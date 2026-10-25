import Charts
import Core
import SwiftUI

/// Workouts per week, month, quarter or year, with the totals of the current one.
struct StatsSection: View {
    let workouts: [Workout]
    @State private var period = Period.week

    var body: some View {
        let periods = stats(workouts, per: period, count: [.week: 12, .month: 12, .quarter: 8, .year: 5][period]!)
        let current = periods[periods.count - 1]
        Section("Statistics") {
            Picker("Period", selection: $period) {
                Text("Week").tag(Period.week)
                Text("Month").tag(Period.month)
                Text("Quarter").tag(Period.quarter)
                Text("Year").tag(Period.year)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Chart(periods, id: \.start) { stats in
                BarMark(x: .value("Period", label(stats.start)), y: .value("Workouts", stats.workouts))
            }
            .frame(height: 140)
            HStack {
                total("Workouts", current.workouts.formatted())
                total("Sets", current.sets.formatted())
                total("Volume", current.volumeKg.formatted(.number.precision(.fractionLength(0))) + " kg")
            }
        }
    }

    private func total(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack {
            Text(value).font(.title2.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func label(_ start: Date) -> String {
        switch period {
        case .week: start.formatted(.dateTime.day().month(.defaultDigits))
        case .month: start.formatted(.dateTime.month(.abbreviated))
        case .quarter: "Q\(Calendar.current.component(.month, from: start) / 3 + 1) \(start.formatted(.dateTime.year(.twoDigits)))"
        case .year: start.formatted(.dateTime.year())
        }
    }
}
