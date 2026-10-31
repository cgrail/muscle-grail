import Foundation
import SQLite3
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

/// `gymBookSample`'s logs in GymBook's full backup, with only the columns the import reads, and its plans: MoDi 1 with
/// a cardio exercise, two sets in lb and three in kg, and the archived Anfang, before it in GymBook's order.
let gymBookBackupSample = sqliteFile("""
    CREATE TABLE ZEXERCISE (Z_PK INTEGER PRIMARY KEY, ZNAME VARCHAR, ZIDENTIFIER VARCHAR);
    CREATE TABLE ZWORKOUT (Z_PK INTEGER PRIMARY KEY, ZNAME VARCHAR, ZARCHIVED INTEGER, ZDISPLAYORDER INTEGER);
    CREATE TABLE ZWORKOUTEXERCISE (Z_PK INTEGER PRIMARY KEY, ZDISPLAYORDER INTEGER, ZEXERCISE INTEGER, ZWORKOUT INTEGER);
    CREATE TABLE ZWORKOUTEXERCISESET (Z_PK INTEGER PRIMARY KEY, ZDISPLAYORDER INTEGER, ZFREQUENCYVALUEMAX INTEGER,
        ZFREQUENCYVALUEMIN INTEGER, ZWORKOUTEXERCISE INTEGER, ZQUANTITYVALUE FLOAT, ZFREQUENCYUNIT VARCHAR, ZQUANTITYUNIT VARCHAR);
    CREATE TABLE ZEXERCISELOG (Z_PK INTEGER PRIMARY KEY, ZSKIPPED INTEGER, ZTIME INTEGER, ZEXERCISE INTEGER, ZWORKOUT INTEGER,
        ZFREQUENCYVALUE INTEGER, ZQUANTITYVALUE FLOAT, ZDAY VARCHAR, ZFREQUENCYUNIT VARCHAR, ZQUANTITYUNIT VARCHAR);
    INSERT INTO ZWORKOUT VALUES (1, 'MoDi 1', 0, 1), (2, 'Anfang', 1, 0);
    INSERT INTO ZEXERCISE VALUES (1, 'Ellipsentrainer', 'ellipticalCycling'), (2, 'Rumpfdrehung am Gerät', 'machineTrunkRotations'),
        (3, 'Schrägbankdrücken mit Kurzhanteln', 'inclineDumbbellBenchPresses'), (4, 'Klimmzüge', 'chinUps');
    INSERT INTO ZWORKOUTEXERCISE VALUES (1, 0, 1, 1), (2, 2, 3, 1), (3, 1, 2, 1), (4, 0, 4, 2);
    INSERT INTO ZWORKOUTEXERCISESET VALUES (1, 0, 15, NULL, 1, 3, 'm', 'km'), (2, 0, 10, NULL, 3, 130, 'x', 'lb'),
        (3, 1, 10, NULL, 3, 130, 'x', 'lb'), (4, 0, 10, NULL, 2, 22, 'x', 'kg'), (5, 1, 10, NULL, 2, 22, 'x', 'kg'),
        (6, 2, NULL, 10, 2, 22, 'x', 'kg'), (7, 0, 8, NULL, 4, NULL, 'x', 'kg');
    INSERT INTO ZEXERCISELOG VALUES (1, 0, 75600, 4, 1, 8, NULL, '2026-10-14', 'x', 'kg'),
        (2, 0, 75240, 1, 1, 15, 3, '2026-10-21', 'm', 'km'), (3, 0, 75780, 2, 1, 10, 130, '2026-10-21', 'x', 'lb'),
        (4, 1, 75780, 2, 1, 12, 130, '2026-10-21', 'x', 'lb'), (5, 0, 76200, 3, 1, 10, 22, '2026-10-21', 'x', 'kg');
    """)

/// A log export with a set of each of `exercises`.
func gymBookFile(_ exercises: String...) -> GymBook.File {
    GymBook.File(logs: exercises.map { GymBook.Log(date: .now, workout: "Push", exercise: $0, reps: 10) })
}

/// The SQLite database `sql` makes, as a file holds it.
func sqliteFile(_ sql: String) -> Data {
    var db: OpaquePointer?
    var size: Int64 = 0
    sqlite3_open(":memory:", &db)
    defer { sqlite3_close(db) }
    sqlite3_exec(db, sql, nil, nil, nil)
    let bytes = sqlite3_serialize(db, "main", &size, 0)
    defer { sqlite3_free(bytes) }
    return Data(bytes: bytes!, count: Int(size))
}

func day(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

@MainActor struct GymBookTests {
    let container = try! Store.makeContainer(inMemory: true)
    var context: ModelContext { container.mainContext }
    let file = try! GymBook.read(gymBookSample)

    var workouts: [Workout] { (try? context.fetch(Workout.history)) ?? [] }

    @Test func aSetReadsWithItsWorkoutTimeRepsAndWeight() {
        #expect(file.logs[3] == GymBook.Log(date: day(21, 21, 10), workout: "MoDi 1", exercise: "Schrägbankdrücken mit Kurzhanteln", reps: 10, weightKg: 22))
    }

    @Test func poundsReadAsKilograms() {
        #expect((file.logs[1].weightKg, file.logs[1].unit) == (WeightUnit.lb.kg(130), .lb))
    }

    @Test func aBackupReadsAsTheLogExport() throws {
        #expect(try GymBook.read(gymBookBackupSample).logs == file.logs)
    }

    @Test func aBackupHasItsPlansTheActiveOnesFirst() throws {
        #expect(try GymBook.read(gymBookBackupSample).plans == [
            GymBook.Plan(name: "MoDi 1", exercises: [ // no cardio
                GymBook.Planned(exercise: "Rumpfdrehung am Gerät", sets: 2, reps: 10, weightKg: WeightUnit.lb.kg(130), unit: .lb),
                GymBook.Planned(exercise: "Schrägbankdrücken mit Kurzhanteln", sets: 3, reps: 10, weightKg: 22),
            ]),
            GymBook.Plan(name: "Anfang", exercises: [GymBook.Planned(exercise: "Klimmzüge", sets: 1, reps: 8)], archived: true),
        ])
    }

    @Test func aBackupHasGymBooksEnglishNames() throws {
        #expect(try GymBook.read(gymBookBackupSample).englishNames["Klimmzüge"] == "chinUps")
    }

    @Test func aFileThatIsNotGymBooksThrows() {
        #expect(throws: (any Error).self) { try GymBook.read(Data("{\"gym\": []}".utf8)) }
        #expect(throws: (any Error).self) { try GymBook.read(Data("<plans/>".utf8)) }
        #expect(throws: (any Error).self) { try GymBook.read(sqliteFile("CREATE TABLE gym (set_id INTEGER)")) }
    }

    @Test func importAddsEachWorkoutWithTheSetsDoneInIt() {
        context.importGymBook(file)
        #expect(workouts.map { $0.exercises.map { $0.sets.map(\.reps) } } == [[[10], [10]], [[8]]]) // no cardio, no skipped set
        #expect(workouts.map(\.start) == [day(21, 21, 3), day(14, 21, 0)])
    }

    @Test func importingAgainAddsNothing() throws {
        #expect(context.importGymBook(file) == 2)
        #expect(context.importGymBook(file) == 0)
        #expect(try context.fetchCount(FetchDescriptor<LoggedSet>()) == 3)
    }

    @Test func aWorkoutNameBecomesAPlanOfItsNewestWorkout() throws {
        context.importGymBook(file)
        let plan = try #require(context.fetch(FetchDescriptor<Plan>()).first)
        #expect(plan.name == "MoDi 1")
        #expect(plan.sortedItems.map { context.exerciseName($0.exerciseID) } == ["Rumpfdrehung am Gerät", "Incline Dumbbell Press"])
        #expect(plan.sortedItems.map(\.targetSets) == [2, 1]) // the skipped set was planned
        #expect(workouts.allSatisfy { $0.plan == plan })
    }

    @Test func aBackupsPlansComeInWithTheirTargets() throws {
        context.importGymBook(try GymBook.read(gymBookBackupSample))
        let plans = try context.fetch(FetchDescriptor<Plan>(sortBy: [SortDescriptor(\.order)]))
        #expect(plans.map(\.name) == ["MoDi 1", "Anfang"])
        #expect(plans[0].sortedItems.map { [$0.targetSets, $0.targetReps] } == [[2, 10], [3, 10]])
        #expect(plans[0].sortedItems.map(\.targetWeightKg) == [WeightUnit.lb.kg(130), 22])
    }

    @Test func aPlanLeftOutLeavesItsWorkoutsWithoutOne() throws {
        context.importGymBook(file, leavingOut: ["MoDi 1"])
        #expect(try context.fetchCount(FetchDescriptor<Plan>()) == 0)
        #expect(workouts.map(\.plan) == [nil, nil])
    }

    @Test func importingAgainMakesNoExerciseOfYourOwn() throws {
        context.importGymBook(file)
        let own = try context.fetchCount(FetchDescriptor<CatalogEntry>())
        context.importGymBook(file, exercises: [:])
        #expect(try context.fetchCount(FetchDescriptor<CatalogEntry>()) == own)
    }

    @Test func aCloseNameInAnyLanguageMatches() {
        let file = GymBook.File(logs: gymBookFile("Beinpressen", "Prensa de piernas", "Drehen").logs, englishNames: ["Drehen": "torsoTwists"])
        #expect(context.gymBookMatches(file) == ["Beinpressen": "leg-press", "Prensa de piernas": "leg-press", "Drehen": "torso-twists"])
    }

    @Test func aNameWithoutAMatchSuggestsTheClosest() {
        #expect(context.gymBookMatches(gymBookFile("Rumpfdrehung am Gerät")).isEmpty)
        #expect(gymBookFile().suggestions(for: "Rumpfdrehung am Gerät").first?.id == "torso-twists")
    }

    @Test func aWorkoutNameWithAPlanKeepsIt() throws {
        let plan = makePlan(context, "squat")
        context.rename(plan, to: "MoDi 1")
        context.importGymBook(file)
        #expect(try context.fetchCount(FetchDescriptor<Plan>()) == 1)
        #expect(plan.sortedItems.map(\.exerciseID) == ["squat"])
        #expect(workouts.allSatisfy { $0.plan == plan })
    }

    @Test func anExerciseIsFoundByItsGermanName() {
        context.importGymBook(file)
        #expect(workouts[0].exercises.map(\.id).last == "incline-db-press")
    }

    @Test func anExerciseWithoutAMatchBecomesYourOwn() throws {
        context.importGymBook(file)
        let id = try #require(workouts[0].exercises.first?.id)
        #expect(context.catalogEntry(id)?.isOwnExercise == true)
        #expect(context.exerciseName(id) == "Rumpfdrehung am Gerät")
    }

    @Test func theExerciseChosenForAGymBookNameIsUsed() {
        context.importGymBook(file, exercises: ["Rumpfdrehung am Gerät": "machine-seated-crunch"])
        #expect(workouts[0].exercises.first?.id == "machine-seated-crunch")
    }

    @Test func anExerciseLastLoggedInPoundsShowsInPounds() {
        context.importGymBook(file, exercises: ["Rumpfdrehung am Gerät": "machine-seated-crunch"])
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
        rebuilt.importGymBook(try GymBook.read(context.gymBookExport()))
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
