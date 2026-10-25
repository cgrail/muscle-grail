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

    @Test func monthsAreLabeledWhereTheyStart() {
        let weeks = activityWeeks(weeks: 6, now: date("2026-10-21"), calendar: calendar) // weeks from 14 September
        #expect(monthLabels(weeks, calendar: calendar) == [0: midnight("2026-09-14"), 3: midnight("2026-10-05")])
    }

    @Test func aMonthLabelRightBeforeTheNextIsLeftOut() {
        let weeks = activityWeeks(weeks: 4, now: date("2026-10-21"), calendar: calendar) // weeks from 28 September
        #expect(monthLabels(weeks, calendar: calendar).keys.sorted() == [1])
    }

    @Test func gymDaysWinOverGoals() {
        let day = date("2026-10-20")
        let week = activityWeeks(gym: [day], steps: [midnight("2026-10-20"): 12_000], stepGoal: 10_000, weeks: 1, now: day, calendar: calendar)[0]
        #expect(week.days == [0, 3, nil, nil, nil, nil, nil])
    }

    @Test func goalDaysShowWhetherEveryGoalWasReached() {
        let steps = [midnight("2026-10-19"): 12_000, midnight("2026-10-20"): 12_000.0]
        let km = [midnight("2026-10-19"): 11, midnight("2026-10-20"): 5.0]
        let week = activityWeeks(steps: steps, km: km, stepGoal: 10_000, kmGoal: 10, weeks: 1, now: date("2026-10-22"), calendar: calendar)[0]
        #expect(week.days == [2, 1, 0, 0, nil, nil, nil]) // both goals, steps only, nothing, today with nothing yet
    }

    @Test func withoutGoalsMovingIsShortOfThem() {
        let week = activityWeeks(steps: [midnight("2026-10-19"): 3_000], weeks: 1, now: date("2026-10-19"), calendar: calendar)[0]
        #expect(week.days[0] == 1)
    }

    @Test func gymSessionsSkipTheWorkoutsThisAppSavedToHealth() {
        let own = workout(on: "2026-10-20")
        let saved = UUID()
        context.savedToHealth(own, as: saved)
        workout(on: "2026-10-21", []) // started, nothing logged
        let health = [(start: date("2026-10-20"), id: saved), (start: date("2026-10-21"), id: UUID())] // the second from the watch or another app
        #expect(gymSessions(all(), health: health).sorted() == [date("2026-10-20"), date("2026-10-21")])
    }

    @Test func aDayShowsTheWorkoutsTrainedOnIt() {
        let monday = workout(on: "2026-10-19")
        workout(on: "2026-10-20")
        workout(on: "2026-10-19", [])
        #expect(trained(all(), on: date("2026-10-19"), calendar: calendar) == [monday])
    }

    @Test func everyWeekdayIsLabeledFromTheFirst() {
        var german = calendar
        german.locale = Locale(identifier: "de_DE")
        #expect(weekdayLabels(calendar: german) == ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"])
    }

    @Test func progressFollowsTheKilometerGoalWhenThereIsOne() {
        #expect(dayProgress(steps: 5_000, km: 2.5, stepGoal: 10_000, kmGoal: 10) == 0.25)
        #expect(dayProgress(steps: 5_000, km: 2.5, stepGoal: 10_000, kmGoal: 0) == 0.5)
    }

    @Test func progressStopsAtTheGoalAndNeedsOne() {
        #expect(dayProgress(steps: 15_000, km: 0, stepGoal: 10_000, kmGoal: 0) == 1)
        #expect(dayProgress(steps: 15_000, km: 9, stepGoal: 0, kmGoal: 0) == nil)
    }

    @Test func unsetGoalsAreTenThousandStepsAndNoKilometers() {
        let goals = dailyGoals() // nothing stored for the tests
        #expect((goals.steps, goals.km) == (10_000, 0))
    }
}
