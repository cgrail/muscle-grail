import SwiftData
import Testing
@testable import Core

@MainActor struct FunnyNamesTests {
    let container = try! Store.makeContainer(inMemory: true)
    var context: ModelContext { container.mainContext }

    @Test func aNewPlanGetsAFunnyNameForWhatItTrains() {
        let plan = context.addPlan()
        context.addNew("squat", to: plan)
        #expect(plan.name == "Leggy")
    }

    @Test func aTypedNameStays() {
        let plan = context.addPlan()
        context.rename(plan, to: "Push")
        context.addNew("squat", to: plan)
        #expect(plan.name == "Push")
    }

    @Test func aPlanOfYourOwnExercisesKeepsItsName() {
        let plan = context.addPlan()
        context.addNew(context.createExercise(named: "Zercher Carry"), to: plan)
        #expect(plan.name == String(localized: "New plan", bundle: .module))
    }

    @Test func aFunnyNameFollowsWhatThePlanTrains() {
        let plan = context.addPlan()
        context.addNew("squat", to: plan)
        context.replace(plan.sortedItems[0], with: "bench-press")
        #expect(plan.name == "Bench Bernie")
    }

    @Test func removingAnExerciseNamesThePlanForWhatIsLeft() {
        let plan = makePlan(context, "squat", "bench-press")
        context.deleteExercise(plan.sortedItems[0])
        #expect(plan.name == "Bench Bernie")
    }

    @Test func movingAnExerciseNamesBothPlans() {
        let from = makePlan(context, "squat", "bench-press"), to = makePlan(context)
        context.move(from.sortedItems[0], to: to)
        #expect([from.name, to.name] == ["Bench Bernie", "Leggy"])
    }

    @Test func plansThatTrainTheSameGetDifferentNames() {
        let first = context.addPlan(), second = context.addPlan()
        context.addNew("squat", to: first)
        context.addNew("squat", to: second)
        #expect(second.name == "Booty")
    }

    @Test func aGermanFunnyNameCountsAsFunny() {
        let plan = context.addPlan()
        context.rename(plan, to: "Beini")
        context.addNew("bench-press", to: plan)
        #expect(plan.name == "Bench Bernie")
    }

    @Test func aFunnyNameOfAnEarlierVersionFollowsWhatThePlanTrains() {
        let plan = context.addPlan()
        context.rename(plan, to: "Quadzilla")
        context.addNew("squat", to: plan)
        #expect(plan.name == "Leggy")
    }

    @Test func theDiceGivesTheNextFunnyName() {
        let plan = context.addPlan()
        context.addNew("squat", to: plan)
        context.rollFunnyName(plan)
        #expect(plan.name == "Booty")
    }

    @Test func aCharactersPlanShowsItsMotto() {
        let plan = context.addPlan()
        context.addNew("squat", to: plan)
        #expect(plan.motto == "Stairs are temporary. Gains are forever.")
    }

    @Test func aTypedNameHasNoMotto() {
        let plan = makePlan(context, "squat")
        context.rename(plan, to: "Legs")
        #expect(plan.motto == nil)
    }

    @Test func everyCharacterIsDrawn() {
        let missing = funnyNames.values.joined().map(\.key).filter {
            Bundle.module.url(forResource: pictureID($0), withExtension: "png", subdirectory: "Characters") == nil
        }
        #expect(missing == [])
    }

    @Test func aPlansPictureIsItsCharacter() {
        let plan = context.addPlan()
        context.addNew("squat", to: plan)
        context.rollFunnyName(plan)
        #expect(plan.picture?.lastPathComponent == "booty.png")
    }

    @Test func aTypedNamesPictureShowsWhatThePlanTrains() {
        let plan = makePlan(context, "bench-press")
        context.rename(plan, to: "Push")
        #expect(plan.picture?.lastPathComponent == "bench-bernie.png")
    }

    @Test func typedNamesSideBySideGetDifferentPictures() {
        let first = makePlan(context, "bench-press"), second = makePlan(context, "bench-press")
        context.rename(first, to: "Push A")
        context.rename(second, to: "Push B")
        #expect(first.picture != second.picture)
    }

    @Test func aPlanOfYourOwnExercisesHasNoPicture() {
        let plan = makePlan(context, context.createExercise(named: "Zercher Carry"))
        #expect(plan.picture == nil)
    }
}
