import Testing
@testable import Core

struct CatalogTests {
    @Test func bundledCatalogDecodesWithImages() throws {
        #expect(CatalogExercise.all.count > 800)
        let bench = try #require(CatalogExercise.all.first { $0.name == "Barbell Bench Press - Medium Grip" })
        #expect(bench.imageURL?.absoluteString.hasSuffix("/0.jpg") == true)
        #expect(bench.matches("chest"))
        #expect(bench.matches("barbell"))
        #expect(!bench.matches("squat"))
    }
}
