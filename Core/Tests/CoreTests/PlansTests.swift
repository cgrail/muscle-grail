import Foundation
import SwiftData
import Testing
@testable import Core

@MainActor struct PlansTests {
    let container = try! Store.makeContainer(inMemory: true)
    var context: ModelContext { container.mainContext }

    @Test func settingOneTargetKeepsTheOthers() {
        let item = makePlan(context, "Bench").sortedItems[0]
        context.setTargets(item, sets: 5)
        context.setTargets(item, reps: 6)
        context.setTargets(item, weightKg: 70)
        #expect((item.targetSets, item.targetReps, item.targetWeightKg) == (5, 6, 70))
    }
}
