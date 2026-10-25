import Core
import SwiftUI

/// How often you trained over the last year, as GitHub shows contributions: gym workouts, and walks from Health on the iPhone.
struct ActivitySection: View {
    let workouts: [Workout]
    @State private var walks: [Date] = []

    var body: some View {
        let gym = workouts.filter { !($0.sets ?? []).isEmpty }.map(\.start)
        Section {
            ActivityGrid(weeks: activityWeeks(gym + walks, weeks: 53))
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
        .task { walks = await Health.walks(since: .now.addingTimeInterval(-371 * 24 * 3600)) }
        #endif
    }
}

/// One column per week, one square per day, darker for more.
struct ActivityGrid: View {
    let weeks: [[Int?]]
    var color = Color.green

    var body: some View {
        let active = weeks.joined().filter { ($0 ?? 0) > 0 }.count
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(weeks.indices, id: \.self) { week in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { day in
                            RoundedRectangle(cornerRadius: 2).fill(fill(weeks[week][day])).frame(width: 11, height: 11)
                        }
                    }
                }
            }
        }
        .defaultScrollAnchor(.trailing)
        .accessibilityElement()
        .accessibilityLabel(Text("Active on \(active) days in the last \(weeks.count) weeks"))
    }

    private func fill(_ count: Int?) -> Color {
        guard let count else { return .clear }
        return count == 0 ? Color.secondary.opacity(0.15) : color.opacity(min(1, 0.4 + 0.3 * Double(count - 1)))
    }
}
