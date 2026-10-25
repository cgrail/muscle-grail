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
        makePlan(context, "Barbell_Squat")
        context.editExercise("Barbell_Squat", details: "Below parallel")
        try context.save()
        try Backup.write(container, to: folder)
        let backup = try JSONDecoder().decode(Backup.File.self, from: Data(contentsOf: file))
        #expect(try backup.gym == context.fetch(FetchDescriptor<Action>(sortBy: [SortDescriptor(\.date)])).map(Backup.Entry.init))
        #expect(try backup.catalog == context.fetch(FetchDescriptor<CatalogAction>()).map(Backup.Entry.init))
    }

    @Test func anEmptyStoreWritesNoBackup() throws {
        try Backup.write(container, to: folder)
        #expect(!FileManager.default.fileExists(atPath: file.path()))
    }
}
