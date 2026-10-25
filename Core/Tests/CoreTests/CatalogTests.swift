import Foundation
import Testing
@testable import Core

struct CatalogTests {
    let bench = CatalogExercise(id: "b", name: "Bench Press", equipment: "barbell", primaryMuscles: ["chest"], images: ["Bench/0.jpg"])

    @Test func bundledCatalogDecodes() {
        #expect(CatalogExercise.all.count > 800)
    }

    @Test func missingOrBrokenCatalogLoadsEmpty() {
        #expect(CatalogExercise.load(nil).isEmpty)
        #expect(CatalogExercise.load(URL(filePath: #filePath)).isEmpty)
    }

    @Test func imageLoadsFromTheRepo() {
        #expect(bench.imageURL?.absoluteString == "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Bench/0.jpg")
    }

    @Test func exerciseWithoutImagesHasNoImageURL() {
        let plank = CatalogExercise(id: "p", name: "Plank", equipment: nil, primaryMuscles: ["abdominals"], images: [])
        #expect(plank.imageURL == nil)
    }

    @Test func detailListsMusclesThenEquipment() {
        #expect(bench.detail == "chest · barbell")
    }

    @Test func searchMatchesNameMusclesAndEquipmentIgnoringCase() {
        #expect(["bench", "CHEST", "bar"].allSatisfy(bench.matches))
        #expect(!bench.matches("squat"))
    }
}
