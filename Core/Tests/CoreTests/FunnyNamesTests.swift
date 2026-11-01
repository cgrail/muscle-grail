import SwiftData
import Testing
@testable import Core

@MainActor struct FunnyNamesTests {
    let container = try! Store.makeContainer(inMemory: true)
    var context: ModelContext { container.mainContext }

    @Test func aNewPlanGetsAFunnyNameForWhatItTrains() {
        let plan = context.addPlan()
        context.addNew("squat", to: plan)
        #expect(plan.name == "Leg Day Sucks")
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
        #expect(plan.name == "International Chest Day")
    }

    @Test func removingAnExerciseNamesThePlanForWhatIsLeft() {
        let plan = makePlan(context, "squat", "bench-press")
        context.deleteExercise(plan.sortedItems[0])
        #expect(plan.name == "International Chest Day")
    }

    @Test func movingAnExerciseNamesBothPlans() {
        let from = makePlan(context, "squat", "bench-press"), to = makePlan(context)
        context.move(from.sortedItems[0], to: to)
        #expect([from.name, to.name] == ["International Chest Day", "Leg Day Sucks"])
    }

    @Test func plansThatTrainTheSameGetDifferentNames() {
        let first = context.addPlan(), second = context.addPlan()
        context.addNew("squat", to: first)
        context.addNew("squat", to: second)
        #expect(second.name == "Quadzilla")
    }

    @Test func aGermanFunnyNameCountsAsFunny() {
        let plan = context.addPlan()
        context.rename(plan, to: "Beintag, na toll")
        context.addNew("bench-press", to: plan)
        #expect(plan.name == "International Chest Day")
    }

    @Test func theDiceGivesTheNextFunnyName() {
        let plan = context.addPlan()
        context.addNew("squat", to: plan)
        context.rollFunnyName(plan)
        #expect(plan.name == "Quadzilla")
    }

    @Test func aPlansPictureIsItsFunnyNamesEmoji() {
        let plan = context.addPlan()
        context.addNew("squat", to: plan)
        context.rollFunnyName(plan)
        #expect(plan.emoji == "🦖")
    }

    @Test func aTypedNamesPictureShowsWhatThePlanTrains() {
        let plan = makePlan(context, "bench-press")
        context.rename(plan, to: "Push")
        #expect(plan.emoji == "🌍")
    }

    @Test func typedNamesSideBySideGetDifferentPictures() {
        let first = makePlan(context, "bench-press"), second = makePlan(context, "bench-press")
        context.rename(first, to: "Push A")
        context.rename(second, to: "Push B")
        #expect(first.emoji != second.emoji)
    }
}
