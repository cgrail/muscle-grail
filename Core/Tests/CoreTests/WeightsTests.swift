import Testing
@testable import Core

struct WeightsTests {
    @Test func dumbbellsGoUpByOneKiloToTenThenByTwo() {
        #expect(Weights.next(after: 5, for: "Dumbbell_Bicep_Curl") == 6)
        #expect(Weights.next(after: 20, for: "Dumbbell_Bicep_Curl") == 22)
        #expect(Weights.previous(before: 12, for: "Dumbbell_Bicep_Curl") == 10)
    }

    @Test func barbellsGoUpByTheSmallestPlates() {
        #expect(Weights.next(after: 60, for: "Barbell_Squat") == 62.5)
    }

    @Test func kettlebellsComeInTheirUsualSizes() {
        #expect(Weights.next(after: 28, for: "Advanced_Kettlebell_Windmill") == 32)
    }

    @Test func machinesGoUpByTheirStack() {
        #expect(Weights.next(after: 40, for: "Ab_Crunch_Machine") == 45)
    }

    @Test func aWeightThatDoesNotExistStepsToTheNearestRealOne() {
        #expect(Weights.next(after: 20.7, for: "Dumbbell_Bicep_Curl") == 22)
        #expect(Weights.previous(before: 20.7, for: "Dumbbell_Bicep_Curl") == 20)
    }

    @Test func ownExercisesStepByPlates() {
        #expect(Weights.next(after: 20, for: "00000000-0000-0000-0000-000000000007") == 22.5)
    }

    @Test func theEndsOfTheRangeHold() {
        #expect(Weights.previous(before: 0, for: "Barbell_Squat") == 0)
        #expect(Weights.next(after: 48, for: "Advanced_Kettlebell_Windmill") == 48)
    }
}
