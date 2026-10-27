import Foundation
import SwiftData
import Testing
@testable import Core

/// GymBook's log export as GymBook in German writes it, newest workout first: a cardio entry, a set in lb and a skipped one,
/// a set of a bundled exercise in kg, and an older workout of the same name with a bodyweight set.
let gymBookSample = """
    <logs>\
    <log><date>21.10.26</date><workout>MoDi 1</workout><time>20:54</time><exercise>Ellipsentrainer</exercise><type>default</type>\
    <time>15\u{202F}Minuten</time><distance>3,00\u{202F}km</distance><notes/><skipped>Nein</skipped></log>\
    <log><date>21.10.26</date><workout>MoDi 1</workout><time>21:03</time><exercise>Rumpfdrehung am Gerät</exercise><type>default</type>\
    <reps>10</reps><weight>130,00\u{202F}lb</weight><notes/><skipped>Nein</skipped></log>\
    <log><date>21.10.26</date><workout>MoDi 1</workout><time>21:03</time><exercise>Rumpfdrehung am Gerät</exercise><type>default</type>\
    <reps>12</reps><weight>130,00\u{202F}lb</weight><notes/><skipped>Ja</skipped></log>\
    <log><date>21.10.26</date><workout>MoDi 1</workout><time>21:10</time><exercise>Schrägbankdrücken mit Kurzhanteln</exercise>\
    <type>default</type><reps>10</reps><weight>22,00\u{202F}kg</weight><notes/><skipped>Nein</skipped></log>\
    <log><date>14.10.26</date><workout>MoDi 1</workout><time>21:00</time><exercise>Klimmzüge</exercise><type>default</type>\
    <reps>8</reps><weight/><notes/><skipped>Nein</skipped></log>\
    </logs>
    """.data(using: .utf16)! // with a byte order mark, as GymBook writes it

func day(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

@MainActor struct GymBookTests {
    let container = try! Store.makeContainer(inMemory: true)
    var context: ModelContext { container.mainContext }
    let logs = try! GymBook.logs(gymBookSample)

    var workouts: [Workout] { (try? context.fetch(Workout.history)) ?? [] }

    @Test func aSetReadsWithItsWorkoutTimeRepsAndWeight() {
        #expect(logs[3] == GymBook.Log(date: day(21, 21, 10), workout: "MoDi 1", exercise: "Schrägbankdrücken mit Kurzhanteln", reps: 10, weightKg: 22))
    }

    @Test func poundsReadAsKilograms() {
        #expect((logs[1].weightKg, logs[1].unit) == (WeightUnit.lb.kg(130), .lb))
    }

    @Test func aFileThatIsNotGymBooksThrows() {
        #expect(throws: (any Error).self) { try GymBook.logs(Data("{\"gym\": []}".utf8)) }
        #expect(throws: (any Error).self) { try GymBook.logs(Data("<plans/>".utf8)) }
    }

    @Test func importAddsEachWorkoutWithTheSetsDoneInIt() {
        context.importGymBook(logs)
        #expect(workouts.map { $0.exercises.map { $0.sets.map(\.reps) } } == [[[10], [10]], [[8]]]) // no cardio, no skipped set
        #expect(workouts.map(\.start) == [day(21, 21, 3), day(14, 21, 0)])
    }

    @Test func importingAgainAddsNothing() throws {
        #expect(context.importGymBook(logs) == 2)
        #expect(context.importGymBook(logs) == 0)
        #expect(try context.fetchCount(FetchDescriptor<LoggedSet>()) == 3)
    }

    @Test func aWorkoutNameBecomesAPlanOfItsNewestWorkout() throws {
        context.importGymBook(logs)
        let plan = try #require(context.fetch(FetchDescriptor<Plan>()).first)
        #expect(plan.name == "MoDi 1")
        #expect(plan.sortedItems.map { context.exerciseName($0.exerciseID) } == ["Rumpfdrehung am Gerät", "Incline Dumbbell Press"])
        #expect(plan.sortedItems.map(\.targetSets) == [2, 1]) // the skipped set was planned
        #expect(workouts.allSatisfy { $0.plan == plan })
    }

    @Test func aWorkoutNameWithAPlanKeepsIt() throws {
        let plan = makePlan(context, "squat")
        context.rename(plan, to: "MoDi 1")
        context.importGymBook(logs)
        #expect(try context.fetchCount(FetchDescriptor<Plan>()) == 1)
        #expect(plan.sortedItems.map(\.exerciseID) == ["squat"])
        #expect(workouts.allSatisfy { $0.plan == plan })
    }

    @Test func anExerciseIsFoundByItsGermanName() {
        context.importGymBook(logs)
        #expect(workouts[0].exercises.map(\.id).last == "incline-db-press")
    }

    @Test func anExerciseWithoutAMatchBecomesYourOwn() throws {
        context.importGymBook(logs)
        let id = try #require(workouts[0].exercises.first?.id)
        #expect(context.catalogEntry(id)?.isOwnExercise == true)
        #expect(context.exerciseName(id) == "Rumpfdrehung am Gerät")
    }

    @Test func theExerciseChosenForAGymBookNameIsUsed() {
        context.importGymBook(logs, exercises: ["Rumpfdrehung am Gerät": "machine-seated-crunch"])
        #expect(workouts[0].exercises.first?.id == "machine-seated-crunch")
    }

    @Test func anExerciseLastLoggedInPoundsShowsInPounds() {
        context.importGymBook(logs, exercises: ["Rumpfdrehung am Gerät": "machine-seated-crunch"])
        #expect(context.weightUnit(of: "machine-seated-crunch") == .lb)
    }

    @Test func exportReadsBackAsTheSameWorkouts() throws {
        let fly = context.createExercise(named: "Cable Fly & Row")
        context.setUnit(fly, to: .lb)
        let plan = makePlan(context, "squat", fly)
        context.rename(plan, to: "Push")
        let workout = context.startWorkout(plan)
        context.log("squat", reps: 5, weightKg: 62.5, in: workout)
        context.log(fly, reps: 12, weightKg: WeightUnit.lb.kg(50), in: workout)
        context.log("squat", reps: 10, weightKg: 0, in: workout)
        context.finish(workout)

        let other = try Store.makeContainer(inMemory: true) // kept: a context traps once its container is gone
        let rebuilt = other.mainContext
        rebuilt.importGymBook(try GymBook.logs(context.gymBookExport()))
        let sets = { (context: ModelContext) in
            try context.fetch(Workout.history).map { workout in
                [workout.title] + workout.exercises.flatMap { exercise in
                    exercise.sets.map { "\(context.exerciseName(exercise.id)) \($0.reps) \($0.weightKg)" }
                }
            }
        }
        #expect(try sets(rebuilt) == sets(context))
    }
}
