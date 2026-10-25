import Foundation
import SwiftData
import Testing
@testable import Core

@MainActor struct StatsTests {
    let container = try! Store.makeContainer(inMemory: true)
    var context: ModelContext { container.mainContext }
    let calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    func date(_ text: String) -> Date { try! Date(text + "T12:00:00Z", strategy: .iso8601) }
    func midnight(_ text: String) -> Date { try! Date(text + "T00:00:00Z", strategy: .iso8601) }

    /// A workout on `day` with one set per entry of `sets` (reps, kg).
    @discardableResult
    func workout(on day: String, _ sets: [(Int, Double)] = [(10, 50)]) -> Workout {
        let workout = context.startWorkout(makePlan(context, "Bench"))
        workout.start = date(day)
        for (reps, kg) in sets { context.log("Bench", reps: reps, weightKg: kg, in: workout) }
        return workout
    }

    func all() -> [Workout] { (try? context.fetch(FetchDescriptor<Workout>())) ?? [] }

    @Test func workoutsCountInTheWeekTheyWereDone() {
        workout(on: "2026-10-19") // Monday
        workout(on: "2026-10-25") // Sunday, same week
        workout(on: "2026-10-12")
        let weeks = stats(all(), per: .week, count: 3, now: date("2026-10-25"), calendar: calendar)
        #expect(weeks.map(\.workouts) == [0, 1, 2])
        #expect(weeks.last?.start == midnight("2026-10-19"))
    }

    @Test func quartersStartInJanuaryAprilJulyAndOctober() {
        workout(on: "2026-08-31")
        let quarters = stats(all(), per: .quarter, count: 2, now: date("2026-11-15"), calendar: calendar)
        #expect(quarters.map(\.start) == [midnight("2026-07-01"), midnight("2026-10-01")])
        #expect(quarters.map(\.workouts) == [1, 0])
    }

    @Test func monthsAndYearsCountToo() {
        workout(on: "2025-12-31")
        workout(on: "2026-01-01")
        #expect(stats(all(), per: .month, count: 2, now: date("2026-01-15"), calendar: calendar).map(\.workouts) == [1, 1])
        #expect(stats(all(), per: .year, count: 2, now: date("2026-01-15"), calendar: calendar).map(\.workouts) == [1, 1])
    }

    @Test func setsRepsAndVolumeAddUp() {
        workout(on: "2026-10-20", [(10, 50), (8, 60)])
        let week = stats(all(), per: .week, count: 1, now: date("2026-10-20"), calendar: calendar)[0]
        #expect((week.sets, week.reps, week.volumeKg) == (2, 18, 980))
    }

    @Test func workoutsWithoutSetsDoNotCount() {
        workout(on: "2026-10-20", [])
        #expect(stats(all(), per: .week, count: 1, now: date("2026-10-20"), calendar: calendar)[0].workouts == 0)
    }

    @Test func activityCountsSessionsPerDayInWeekColumns() {
        let days = [date("2026-10-19"), date("2026-10-19"), date("2026-10-14")]
        let weeks = activityWeeks(days, weeks: 2, now: date("2026-10-21"), calendar: calendar)
        #expect(weeks[0].days == [0, 0, 1, 0, 0, 0, 0]) // Monday 12 October to Sunday 18
        #expect(weeks[1].days == [2, 0, 0, nil, nil, nil, nil]) // up to Wednesday 21, the rest still ahead
    }

    @Test func goalDaysShowHowFarTheyGot() {
        let values = [midnight("2026-10-19"): 12_000, midnight("2026-10-20"): 6_000, midnight("2026-10-21"): 2_000.0]
        let week = goalWeeks(values, goal: 10_000, weeks: 1, now: date("2026-10-22"), calendar: calendar)[0]
        #expect(week.days == [3, 2, 1, 0, nil, nil, nil])
    }

    @Test func monthsAreLabeledWhereTheyStart() {
        let weeks = activityWeeks([], weeks: 6, now: date("2026-10-21"), calendar: calendar) // weeks from 14 September
        #expect(monthLabels(weeks, calendar: calendar) == [0: midnight("2026-09-14"), 3: midnight("2026-10-05")])
    }

    @Test func aMonthLabelRightBeforeTheNextIsLeftOut() {
        let weeks = activityWeeks([], weeks: 4, now: date("2026-10-21"), calendar: calendar) // weeks from 28 September
        #expect(monthLabels(weeks, calendar: calendar).keys.sorted() == [1])
    }

    @Test func everyOtherWeekdayIsLabeledFromTheFirst() {
        var english = calendar
        english.locale = Locale(identifier: "en_US")
        #expect(weekdayLabels(calendar: english) == [nil, "Tue", nil, "Thu", nil, "Sat", nil])
    }
}
