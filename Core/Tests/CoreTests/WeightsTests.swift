import Testing
@testable import Core

struct WeightsTests {
    @Test func dumbbellsGoUpByOneKiloToTenThenByTwo() {
        #expect(Weights.next(after: 5, for: "bicep-curl") == 6)
        #expect(Weights.next(after: 20, for: "bicep-curl") == 22)
        #expect(Weights.previous(before: 12, for: "bicep-curl") == 10)
    }

    @Test func typedWeightTakesACommaOrAPoint() {
        #expect(Weights.parse("62,5") == 62.5)
        #expect(Weights.parse(" 62.5 ") == 62.5)
    }

    @Test func typedTextThatIsNoWeightIsIgnored() {
        #expect(["", "abc", "-5", "inf", "nan"].allSatisfy { Weights.parse($0) == nil })
    }

    @Test func barbellsGoUpByTheSmallestPlates() {
        #expect(Weights.next(after: 60, for: "squat") == 62.5)
    }

    @Test func kettlebellsComeInTheirUsualSizes() {
        #expect(Weights.next(after: 28, for: "kettlebell-swing") == 32)
    }

    @Test func machinesGoUpByTheirStack() {
        #expect(Weights.next(after: 40, for: "machine-seated-crunch") == 45)
    }

    @Test func aWeightThatDoesNotExistStepsToTheNearestRealOne() {
        #expect(Weights.next(after: 20.7, for: "bicep-curl") == 22)
        #expect(Weights.previous(before: 20.7, for: "bicep-curl") == 20)
    }

    @Test func ownExercisesStepByPlates() {
        #expect(Weights.next(after: 20, for: "00000000-0000-0000-0000-000000000007") == 22.5)
    }

    @Test func theEndsOfTheRangeHold() {
        #expect(Weights.previous(before: 0, for: "squat") == 0)
        #expect(Weights.next(after: 48, for: "kettlebell-swing") == 48)
    }
}
