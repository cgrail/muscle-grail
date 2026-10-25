import Foundation

public enum Period: String, CaseIterable, Identifiable, Sendable {
    case week, month, quarter, year

    public var id: Self { self }

    /// The start of the period that contains `date`.
    func start(of date: Date, in calendar: Calendar) -> Date {
        switch self {
        case .week: calendar.dateInterval(of: .weekOfYear, for: date)!.start
        case .month: calendar.dateInterval(of: .month, for: date)!.start
        case .quarter: // Calendar's own quarters aren't reliable, so count back from the month
            calendar.date(byAdding: .month, value: -((calendar.component(.month, from: date) - 1) % 3), to: Period.month.start(of: date, in: calendar))!
        case .year: calendar.dateInterval(of: .year, for: date)!.start
        }
    }

    /// The start of the period `steps` periods after the one starting at `start`.
    func start(_ steps: Int, after start: Date, in calendar: Calendar) -> Date {
        switch self {
        case .week: calendar.date(byAdding: .weekOfYear, value: steps, to: start)!
        case .month: calendar.date(byAdding: .month, value: steps, to: start)!
        case .quarter: calendar.date(byAdding: .month, value: 3 * steps, to: start)!
        case .year: calendar.date(byAdding: .year, value: steps, to: start)!
        }
    }
}

public struct PeriodStats: Equatable, Sendable {
    public let start: Date
    public var workouts = 0
    public var sets = 0
    public var reps = 0
    /// Reps times weight, over every set.
    public var volumeKg = 0.0
}

/// The last `count` periods up to the one containing `now`, oldest first. A workout without sets doesn't count.
public func stats(_ workouts: [Workout], per period: Period, count: Int, now: Date = .now, calendar: Calendar = .current) -> [PeriodStats] {
    let current = period.start(of: now, in: calendar)
    var periods = (0..<count).map { PeriodStats(start: period.start($0 - count + 1, after: current, in: calendar)) }
    for workout in workouts {
        let sets = workout.sets ?? []
        guard !sets.isEmpty, let index = periods.firstIndex(where: { $0.start == period.start(of: workout.start, in: calendar) }) else { continue }
        periods[index].workouts += 1
        periods[index].sets += sets.count
        periods[index].reps += sets.map(\.reps).reduce(0, +)
        periods[index].volumeKg += sets.map { Double($0.reps) * $0.weightKg }.reduce(0, +)
    }
    return periods
}

/// Activity as GitHub shows it: one column per week up to the one containing `now`, one row per weekday from the
/// calendar's first, counting the sessions (workouts, walks) on each day. Days after `now` are nil.
public func activityWeeks(_ sessions: [Date], weeks: Int, now: Date = .now, calendar: Calendar = .current) -> [[Int?]] {
    let today = calendar.startOfDay(for: now)
    let counts = Dictionary(sessions.map { (calendar.startOfDay(for: $0), 1) }, uniquingKeysWith: +)
    let thisWeek = Period.week.start(of: now, in: calendar)
    return (0..<weeks).map { week in
        let start = Period.week.start(week - weeks + 1, after: thisWeek, in: calendar)
        return (0..<7).map { day in
            let date = calendar.date(byAdding: .day, value: day, to: start)!
            return date > today ? nil : counts[date, default: 0]
        }
    }
}
