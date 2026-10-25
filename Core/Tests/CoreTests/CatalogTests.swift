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

    @Test func searchFindsEveryWordAnywhere() {
        #expect(bench.matches("barbell press"))
        #expect(!bench.matches("barbell curl"))
    }

    @Test func searchIgnoresPluralsAndHyphens() {
        #expect(CatalogExercise.byID["Barbell_Squat"]?.matches("squats") == true)
        #expect(CatalogExercise.byID["Pullups"]?.matches("pull-ups") == true)
    }

    @Test func assistantSearchListsYourOwnExercisesFirst() {
        let names = catalogNames(matching: "fly", custom: ["Cable Fly", "Squat"], limit: 3)
        #expect(names.first == "Cable Fly")
        #expect(names.count == 3)
    }

    @Test func searchMatchesNameMusclesAndEquipmentIgnoringCase() {
        #expect(["bench", "CHEST", "bar"].allSatisfy(bench.matches))
        #expect(!bench.matches("squat"))
    }
}
