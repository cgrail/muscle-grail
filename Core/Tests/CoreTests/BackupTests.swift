import Foundation
import SwiftData
import Testing
@testable import Core

@MainActor struct BackupTests {
    let container = try! Store.makeContainer(inMemory: true)
    var context: ModelContext { container.mainContext }
    let folder = URL.temporaryDirectory.appending(path: "Backup-\(UUID())")
    var file: URL { folder.appending(path: Backup.fileName) }

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    @Test func backupHoldsBothLogs() throws {
        makePlan(context, "squat")
        context.editExercise("squat", details: "Below parallel")
        try context.save()
        try Backup.write(container, to: folder)
        let backup = try JSONDecoder().decode(Backup.File.self, from: Data(contentsOf: file))
        #expect(try backup.gym == context.fetch(FetchDescriptor<Action>(sortBy: [SortDescriptor(\.date)])).map(Backup.Entry.init))
        #expect(try backup.catalog == context.fetch(FetchDescriptor<CatalogAction>()).map(Backup.Entry.init))
    }

    @Test func restoringReplacesTheStoreWithTheBackup() throws {
        let workout = context.startWorkout(makePlan(context, "squat"))
        context.log("squat", reps: 5, weightKg: 100, in: workout)
        context.setPhoto("squat", to: testPhoto())
        try context.save()
        try Backup.write(container, to: folder)
        let backedUp = try snapshot(context)
        context.deleteWorkout(workout)
        makePlan(context, "pull-up")
        try Backup.restore(file, into: context)
        #expect(try snapshot(context) == backedUp)
    }

    @Test func restoredBackupKeepsWhoMadeEachChange() throws {
        makePlan(context)
        let action = try #require(context.fetch(FetchDescriptor<Action>()).first)
        action.author = "Partner"
        try context.save()
        try Backup.write(container, to: folder)
        try Backup.restore(file, into: context)
        #expect(try context.fetch(FetchDescriptor<Action>()).map(\.author) == ["Partner"])
    }

    @Test func aBrokenBackupChangesNothing() throws {
        makePlan(context, "squat")
        let before = try snapshot(context)
        try Data("not a backup".utf8).write(to: file)
        #expect(throws: (any Error).self) { try Backup.restore(file, into: context) }
        #expect(try snapshot(context) == before)
    }

    @Test func anEmptyStoreWritesNoBackup() throws {
        try Backup.write(container, to: folder)
        #expect(!FileManager.default.fileExists(atPath: file.path()))
    }
}
