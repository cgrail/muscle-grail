import Foundation
import SwiftData
@testable import Core

/// A plan with these exercises, in order.
@MainActor @discardableResult
func makePlan(_ context: ModelContext, _ exercises: String...) -> Plan {
    let plan = context.addPlan()
    for exercise in exercises { context.add(exercise, to: plan) }
    return plan
}

/// A private defaults domain, removed when the test ends.
final class TestDefaults {
    let name = "CoreTests-\(UUID())"
    var defaults: UserDefaults { UserDefaults(suiteName: name)! }

    deinit { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
}

/// The whole model as sorted lines, to compare two stores.
@MainActor func snapshot(_ context: ModelContext) throws -> [String] {
    let plans = try context.fetch(FetchDescriptor<Plan>()).map { "plan \($0.id) \($0.name) \($0.order)" }
    let items = try context.fetch(FetchDescriptor<PlanItem>()).map {
        "item \($0.id) \(String(describing: $0.plan?.id)) \($0.exercise) \($0.order) \($0.targetSets) \($0.targetReps) \($0.targetWeightKg)"
    }
    let workouts = try context.fetch(FetchDescriptor<Workout>()).map {
        "workout \($0.id) \(String(describing: $0.plan?.id)) \($0.start) \(String(describing: $0.end)) \(String(describing: $0.healthKitID))"
    }
    let sets = try context.fetch(FetchDescriptor<LoggedSet>()).map {
        "set \($0.id) \(String(describing: $0.workout?.id)) \($0.exercise) \($0.reps) \($0.weightKg) \($0.date.timeIntervalSinceReferenceDate)"
    }
    return (plans + items + workouts + sets).sorted()
}
