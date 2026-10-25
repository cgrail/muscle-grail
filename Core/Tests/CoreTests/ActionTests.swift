import Foundation
import SwiftData
import Testing
@testable import Core

@MainActor struct ActionTests {
    let container = try! Store.makeContainer(inMemory: true)
    var context: ModelContext { container.mainContext }

    /// Every kind of change, made the way the apps make them.
    func makeEveryChange() {
        let plan = makePlan(context, "Bench", "Squat", "Row")
        context.rename(plan, to: "Push")
        let items = plan.sortedItems
        context.rename(items[1], to: "Front Squat")
        context.setTargets(items[0], sets: 5, reps: 5, weightKg: 80)
        context.reorder(items, fromOffsets: [2], toOffset: 0)
        context.deleteExercise(items[1])
        let workout = context.startWorkout(plan)
        let mistake = context.log("Bench", reps: 50, weightKg: 80, in: workout)
        context.log("Bench", reps: 5, weightKg: 80, in: workout)
        context.undo(mistake)
        context.finish(workout)
        context.savedToHealth(workout, as: UUID())
        context.deleteWorkout(context.startWorkout(plan))
        context.deletePlan(context.addPlan())
    }

    /// An action from a newer app version, in a format this one can't read.
    func insertNewerAction() {
        let action = Action()
        action.version = Change.version + 1
        action.payload = Data(#"{"superset":{}}"#.utf8)
        context.insert(action)
    }

    @Test func replayingTheLogRebuildsTheModel() throws {
        makeEveryChange()
        let rebuilt = try Store.makeContainer(inMemory: true)
        try context.replay(into: rebuilt.mainContext)
        #expect(try snapshot(rebuilt.mainContext) == snapshot(context))
    }

    @Test func replayingTheLogIntoTheSameStoreChangesNothing() throws {
        makeEveryChange()
        let before = try snapshot(context)
        try context.replay(into: context)
        #expect(try snapshot(context) == before)
    }

    @Test func replaySkipsChangesItCannotRead() throws {
        insertNewerAction()
        makePlan(context, "Bench")
        let rebuilt = try Store.makeContainer(inMemory: true)
        try context.replay(into: rebuilt.mainContext)
        #expect(try snapshot(rebuilt.mainContext) == snapshot(context))
    }

    /// What version 1 writes, frozen: every later version must read it, so an old app's workouts always count.
    @Test func everyVersion1ChangeStillReads() throws {
        let version1 = [
            #"{"addPlan":{"id":"00000000-0000-0000-0000-000000000001","name":"Push","order":0}}"#,
            #"{"renamePlan":{"id":"00000000-0000-0000-0000-000000000001","name":"Push day"}}"#,
            #"{"deletePlan":{"id":"00000000-0000-0000-0000-000000000001"}}"#,
            #"{"addExercise":{"exercise":"Bench","id":"00000000-0000-0000-0000-000000000002","order":0,"plan":"00000000-0000-0000-0000-000000000001"}}"#,
            #"{"renameExercise":{"exercise":"Bench Press","id":"00000000-0000-0000-0000-000000000002"}}"#,
            #"{"setTargets":{"id":"00000000-0000-0000-0000-000000000002","reps":5,"sets":5,"weightKg":80}}"#,
            #"{"deleteExercise":{"id":"00000000-0000-0000-0000-000000000002"}}"#,
            #"{"reorder":{"ids":["00000000-0000-0000-0000-000000000002","00000000-0000-0000-0000-000000000003"]}}"#,
            #"{"startWorkout":{"id":"00000000-0000-0000-0000-000000000004","plan":"00000000-0000-0000-0000-000000000001","start":800000000}}"#,
            #"{"logSet":{"date":800000000,"exercise":"Bench","id":"00000000-0000-0000-0000-000000000005","reps":8,"weightKg":60,"workout":"00000000-0000-0000-0000-000000000004"}}"#,
            #"{"deleteSet":{"id":"00000000-0000-0000-0000-000000000005"}}"#,
            #"{"finishWorkout":{"end":800000000,"id":"00000000-0000-0000-0000-000000000004"}}"#,
            #"{"savedToHealth":{"healthKitID":"00000000-0000-0000-0000-000000000006","workout":"00000000-0000-0000-0000-000000000004"}}"#,
            #"{"deleteWorkout":{"id":"00000000-0000-0000-0000-000000000004"}}"#,
        ]
        for json in version1 {
            #expect(throws: Never.self, "\(json)") { try JSONDecoder().decode(Change.self, from: Data(json.utf8)) }
        }
    }

    @Test func actionsFromANewerVersionLockPlanEditing() throws {
        insertNewerAction()
        #expect(try context.fetchCount(Action.newer) == 1)
    }

    @Test func trainingWorksBesideNewerActions() {
        insertNewerAction()
        let workout = context.startWorkout(makePlan(context, "Bench"))
        context.log("Bench", reps: 8, weightKg: 60, in: workout)
        context.finish(workout)
        #expect(workout.sets(of: "Bench").count == 1)
    }
}
