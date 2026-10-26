import Foundation
import SwiftData
import Testing
@testable import Core

@MainActor struct ExercisesTests {
    let container = try! Store.makeContainer(inMemory: true)
    var context: ModelContext { container.mainContext }

    @Test func customExerciseIsNamedByItsEntry() {
        let id = context.createExercise(named: "Cable Fly")
        #expect(exerciseName(id, entry: context.catalogEntry(id)) == "Cable Fly")
    }

    @Test func bundledExerciseKeepsItsNameWhenOnlyItsDetailsChange() {
        context.editExercise("squat", details: "Below parallel")
        #expect(exerciseName("squat", entry: context.catalogEntry("squat")) == "Barbell Back Squat")
    }

    @Test func entryWithoutANameForAnExerciseNotBundledIsNoExerciseOfYourOwn() {
        context.editExercise("Old_Catalog_Curl", details: "Slow")
        #expect(context.catalogEntry("Old_Catalog_Curl")?.isOwnExercise == false)
    }

    @Test func customExerciseWhoseEntryHasNotSyncedGetsAPlaceholder() {
        #expect(exerciseName(UUID().uuidString, entry: nil) == "Custom exercise")
    }

    @Test func bundledExerciseComesWithItsInstructions() {
        #expect(instructions("squat", entry: nil).count == 5)
    }

    @Test func yourDescriptionReplacesTheBundledInstructions() {
        context.editExercise("squat", details: "Below parallel")
        #expect(instructions("squat", entry: context.catalogEntry("squat")) == ["Below parallel"])
    }

    @Test func yourVideoLinkIsTheVideo() {
        context.editExercise("squat", videoURL: "https://example.com/squat")
        #expect(videoURL("squat", entry: context.catalogEntry("squat"))?.absoluteString == "https://example.com/squat")
    }

    @Test func withoutYourLinkTheVideoIsAYouTubeSearch() {
        #expect(videoURL("squat", entry: nil)?.absoluteString == "https://www.youtube.com/results?search_query=Barbell%20Back%20Squat%20form")
    }

    @Test func customExercisesWithTheSameNameNeverShareAnID() {
        #expect(context.createExercise(named: "Cable Fly") != context.createExercise(named: "Cable Fly"))
    }

    @Test func catalogLivesInItsOwnStoreAndLog() throws {
        let id = context.createExercise(named: "Cable Fly")
        context.setPhoto(id, to: testPhoto())
        try context.save()
        let entry = try #require(context.catalogEntry(id))
        let plan = makePlan(context, id)
        try context.save()
        #expect(entry.persistentModelID.storeIdentifier != plan.persistentModelID.storeIdentifier)
        #expect(try context.fetchCount(FetchDescriptor<CatalogAction>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<Action>()) == 2) // the plan and its exercise
    }

    @Test func photoIsShrunkToSync() throws {
        let id = context.createExercise(named: "Cable Fly")
        context.setPhoto(id, to: testPhoto(width: 3000, height: 1500))
        let photo = try #require(context.catalogEntry(id)?.photo.flatMap(Photo.image))
        #expect((photo.width, photo.height) == (1024, 512))
    }

    @Test func dataThatIsNotAPhotoKeepsThePhoto() {
        let id = context.createExercise(named: "Cable Fly")
        context.setPhoto(id, to: testPhoto())
        context.setPhoto(id, to: Data("not a photo".utf8))
        #expect(context.catalogEntry(id)?.photo != nil)
    }

    @Test func removingThePhoto() {
        let id = context.createExercise(named: "Cable Fly")
        context.setPhoto(id, to: testPhoto())
        context.setPhoto(id, to: nil)
        #expect(context.catalogEntry(id)?.photo == nil)
    }
}

@MainActor struct PhotoCacheTests {
    let container = try! Store.makeContainer(inMemory: true)
    var context: ModelContext { container.mainContext }
    let cache = PhotoCache(folder: URL.temporaryDirectory.appending(path: UUID().uuidString))

    @Test func photosDownloadOnceAndShowWithoutNetwork() async {
        await cache.download(["squat", "squat"]) { _ in testPhoto() }
        await cache.download(["squat"]) { _ in Issue.record("downloaded again"); return Data() }
        #expect(cache.image(for: "squat", entry: nil) != nil)
    }

    @Test func withoutNetworkThereIsNoPhoto() async {
        await cache.download(["squat"]) { _ in throw URLError(.notConnectedToInternet) }
        #expect(cache.image(for: "squat", entry: nil) == nil)
    }

    @Test func yourOwnPhotoComesFirst() {
        let id = context.createExercise(named: "Cable Fly")
        context.setPhoto(id, to: testPhoto())
        #expect(cache.image(for: id, entry: context.catalogEntry(id)) != nil)
    }
}
