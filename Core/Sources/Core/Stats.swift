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
        periods[index].volumeKg += workout.volumeKg
    }
    return periods
}

/// Gym days in the activity grid: this app's workouts with sets, and Health's strength workouts it didn't save itself.
public func gymSessions(_ workouts: [Workout], health: [(start: Date, id: UUID)]) -> [Date] {
    workouts.filter { $0.sets?.isEmpty == false }.map(\.start) + healthOnly(health, besides: workouts)
}

/// Health's workouts this app didn't save: from another app, or from the watch before its record synced here.
public func healthOnly(_ health: [(start: Date, id: UUID)], besides workouts: [Workout]) -> [Date] {
    let saved = Set(workouts.compactMap(\.healthKitID))
    return health.filter { !saved.contains($0.id) }.map(\.start)
}

/// This app's workouts with sets on `day`.
public func trained(_ workouts: [Workout], on day: Date, calendar: Calendar = .current) -> [Workout] {
    workouts.filter { $0.sets?.isEmpty == false && calendar.isDate($0.start, inSameDayAs: day) }
}

/// The activity grid, one level per day: 3 a gym day, 2 every daily goal set was reached, 1 moving but short of them
/// (or no goals set), 0 nothing recorded. `steps` and `km` are by start of day.
public func activityWeeks(gym: [Date] = [], steps: [Date: Double] = [:], km: [Date: Double] = [:], stepGoal: Double = 0, kmGoal: Double = 0,
                          weeks: Int, now: Date = .now, calendar: Calendar = .current) -> [GridWeek] {
    let gymDays = Set(gym.map { calendar.startOfDay(for: $0) })
    return dayGrid(weeks: weeks, now: now, calendar: calendar) { day in
        let moved = [(steps[day] ?? 0, stepGoal), (km[day] ?? 0, kmGoal)]
        let goals = moved.filter { $0.1 > 0 }
        if gymDays.contains(day) { return 3 }
        if !goals.isEmpty, goals.allSatisfy({ $0.0 >= $0.1 }) { return 2 }
        return moved.contains { $0.0 > 0 } ? 1 : 0
    }
}

/// One column per week up to the one containing `now`, one row per weekday, `level` for each day up to today.
private func dayGrid(weeks: Int, now: Date, calendar: Calendar, level: (Date) -> Int) -> [GridWeek] {
    let today = calendar.startOfDay(for: now)
    let thisWeek = Period.week.start(of: now, in: calendar)
    return (0..<weeks).map { week in
        let start = Period.week.start(week - weeks + 1, after: thisWeek, in: calendar)
        return GridWeek(start: start, days: (0..<7).map { day in
            let date = calendar.date(byAdding: .day, value: day, to: start)!
            return date > today ? nil : level(date)
        })
    }
}

/// One column of a day grid: the week starting at `start`, and a level for each day, nil for days still ahead.
public struct GridWeek: Equatable, Sendable {
    public let start: Date
    public let days: [Int?]
}

/// GitHub's month row: the columns where a new month starts, with the date to name it by. A first label
/// right before the next one is left out, so the two don't overlap.
public func monthLabels(_ weeks: [GridWeek], calendar: Calendar = .current) -> [Int: Date] {
    let starts = weeks.indices.filter { $0 == 0 || calendar.component(.month, from: weeks[$0].start) != calendar.component(.month, from: weeks[$0 - 1].start) }
    let shown = starts.count > 1 && starts[1] <= 2 ? Array(starts.dropFirst()) : starts
    return Dictionary(uniqueKeysWithValues: shown.map { ($0, weeks[$0].start) })
}

/// The weekday column: every row named, counting from the calendar's first weekday (Mo, Di, Mi … in German).
public func weekdayLabels(calendar: Calendar = .current) -> [String] {
    (0..<7).map { calendar.shortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + $0) % 7] }
}

/// The daily goals in iCloud's key-value store, where the iPhone app keeps them: 10,000 steps unless set, km off at 0.
/// The widget and the complication read them from there too.
public func dailyGoals(in store: NSUbiquitousKeyValueStore = .default) -> (steps: Double, km: Double) {
    (store.object(forKey: "goalSteps") == nil ? 10_000 : store.double(forKey: "goalSteps"), store.double(forKey: "goalKm"))
}

/// How far today got toward the daily goal, from 0 to 1, for a ring or a bar: kilometers when a km goal is set,
/// else steps. Nil without either goal.
public func dayProgress(steps: Double, km: Double, stepGoal: Double, kmGoal: Double) -> Double? {
    if kmGoal > 0 { return min(km / kmGoal, 1) }
    return stepGoal > 0 ? min(steps / stepGoal, 1) : nil
}
