import Core
import SwiftUI

/// How often you trained over the last year, as GitHub shows contributions: gym workouts, and on the iPhone every workout in Health.
struct ActivitySection: View {
    let workouts: [Workout]
    @State private var health: [(start: Date, id: UUID)] = []

    var body: some View {
        Section {
            ActivityGrid(weeks: activityWeeks(activitySessions(workouts, health: health), weeks: 53))
        } header: {
            Text("Activity")
        } footer: {
            #if os(iOS)
            Text("Darker days had more workouts and walks.")
            #else
            Text("Darker days had more workouts.")
            #endif
        }
        #if os(iOS)
        .task { health = await Health.workouts(since: .now.addingTimeInterval(-371 * 24 * 3600)) }
        #endif
    }
}

/// One column per week, one square per day, darker for more, with GitHub's month and weekday labels.
struct ActivityGrid: View {
    let weeks: [GridWeek]
    var color = Color.green

    var body: some View {
        let active = weeks.flatMap(\.days).filter { ($0 ?? 0) > 0 }.count
        let months = monthLabels(weeks)
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .trailing, spacing: 3) {
                label("").frame(height: 12)
                ForEach(Array(weekdayLabels().enumerated()), id: \.offset) { label($0.element ?? "").frame(height: 11) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 3) {
                    ForEach(weeks.indices, id: \.self) { week in
                        VStack(spacing: 3) {
                            label(months[week]?.formatted(.dateTime.month(.abbreviated)) ?? "")
                                .fixedSize() // a month's name runs on over the next columns
                                .frame(width: 11, height: 12, alignment: .leading)
                            ForEach(0..<7, id: \.self) { day in
                                RoundedRectangle(cornerRadius: 2).fill(fill(weeks[week].days[day])).frame(width: 11, height: 11)
                                    .overlay { // today: the last day that isn't still ahead
                                        if week == weeks.count - 1, day == weeks[week].days.lastIndex(where: { $0 != nil }) {
                                            RoundedRectangle(cornerRadius: 2).stroke(.primary.opacity(0.6), lineWidth: 1)
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            .defaultScrollAnchor(.trailing)
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Active on \(active) days in the last \(weeks.count) weeks"))
    }

    private func label(_ text: String) -> some View {
        Text(verbatim: text).font(.system(size: 9)).foregroundStyle(.secondary)
    }

    private func fill(_ count: Int?) -> Color {
        guard let count else { return .clear }
        return count == 0 ? Color.secondary.opacity(0.15) : color.opacity(min(1, 0.4 + 0.3 * Double(count - 1)))
    }
}
