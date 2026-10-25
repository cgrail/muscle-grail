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
