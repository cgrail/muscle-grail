import Foundation
import SwiftData
import Testing
@testable import Core

@MainActor struct FunnyNamesTests {
    let container = try! Store.makeContainer(inMemory: true)
    var context: ModelContext { container.mainContext }

    func character(_ id: String) -> FunnyCharacter { allCharacters.first { $0.id == id }! }

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
        #expect(allCharacters.filter { $0.picture == nil }.map(\.id) == [])
    }

    @Test func aPlansPictureIsItsCharacter() {
        let plan = context.addPlan()
        context.addNew("squat", to: plan)
        context.rollFunnyName(plan)
        #expect(plan.character?.id == "booty")
    }

    @Test func aTypedNamesPictureShowsWhatThePlanTrains() {
        let plan = makePlan(context, "bench-press")
        context.rename(plan, to: "Push")
        #expect(plan.character?.id == "bench-bernie")
    }

    @Test func typedNamesSideBySideGetDifferentPictures() {
        let first = makePlan(context, "bench-press"), second = makePlan(context, "bench-press")
        context.rename(first, to: "Push A")
        context.rename(second, to: "Push B")
        #expect(first.character != second.character)
    }

    @Test func aPlanOfYourOwnExercisesHasNoPicture() {
        let plan = makePlan(context, context.createExercise(named: "Zercher Carry"))
        #expect(plan.character == nil)
    }

    @Test func aChosenPictureStaysWhateverTheName() {
        let plan = makePlan(context, "squat")
        context.choosePicture(character("booty"), for: plan)
        context.rename(plan, to: "Legs")
        #expect(plan.character?.id == "booty")
    }

    @Test func choosingThePictureItShowsAnywayFollowsTheNameAgain() {
        let plan = context.addPlan()
        context.addNew("squat", to: plan)
        context.choosePicture(character("booty"), for: plan)
        context.choosePicture(character("leggy"), for: plan)
        #expect(plan.picture == "")
    }

    @Test func namingAfterACharacterShowsItsDrawing() {
        let plan = makePlan(context, "squat")
        context.choosePicture(character("booty"), for: plan)
        context.name(plan, after: character("squatzilla"))
        #expect(plan.character?.id == "squatzilla")
    }

    @Test func theNamesForWhatAPlanTrainsComeFirst() {
        let plan = makePlan(context, "squat")
        #expect(plan.funnyNameChoices.proposals.map(\.name) == funnyNames[.legs]?.map(\.key))
    }

    @Test func everyOtherFunnyNameFollowsOnce() {
        let choices = makePlan(context, "squat").funnyNameChoices
        #expect((choices.proposals + choices.others).sorted { $0.id < $1.id } == allCharacters.sorted { $0.id < $1.id })
    }

    @Test func aPlanOfYourOwnExercisesOffersEveryFunnyName() {
        let plan = makePlan(context, context.createExercise(named: "Zercher Carry"))
        #expect(plan.funnyNameChoices.others == allCharacters)
    }
}
