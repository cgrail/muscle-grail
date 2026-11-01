import Foundation
import SwiftData

public extension Workout {
    /// The workouts that started in `interval`, newest first.
    static func history(in interval: DateInterval) -> FetchDescriptor<Workout> {
        let (start, end) = (interval.start, interval.end)
        return FetchDescriptor(predicate: #Predicate { $0.start >= start && $0.start < end }, sortBy: [SortDescriptor(\.start, order: .reverse)])
    }
}

/// The years or months with workouts, newest first, each with how many of them were trained. A workout without sets
/// doesn't count, like in `stats`, but still opens its period, where it can be deleted.
public func periods(_ workouts: [Workout], per period: Period, calendar: Calendar = .current) -> [(interval: DateInterval, count: Int)] {
    let byStart = Dictionary(grouping: workouts) { period.start(of: $0.start, in: calendar) }
    return byStart.keys.sorted(by: >).map { start in
        (interval: DateInterval(start: start, end: period.start(1, after: start, in: calendar)),
         count: byStart[start]!.filter { $0.sets?.isEmpty == false }.count)
    }
}

/// How often each training was done, by its plan's name, most often first. A workout without sets doesn't count.
public func timesDone(_ workouts: [Workout]) -> [(title: String, count: Int)] {
    Dictionary(grouping: workouts.filter { $0.sets?.isEmpty == false }) { $0.title }
        .map { (title: $0.key, count: $0.value.count) }
        .sorted { ($1.count, $0.title) < ($0.count, $1.title) }
}
