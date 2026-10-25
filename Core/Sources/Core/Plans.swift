import Foundation
import SwiftData
import SwiftUI

/// Plans and their exercises keep their position in `order`, since CloudKit has no ordered relationships.
public protocol Ordered: AnyObject {
    var order: Int { get set }
}

extension Plan: Ordered {}
extension PlanItem: Ordered {}

public extension Array where Element: Ordered {
    /// Applies a `List.onMove` by renumbering `order`.
    func reorder(fromOffsets source: IndexSet, toOffset destination: Int) {
        var moved = self
        moved.move(fromOffsets: source, toOffset: destination)
        for (index, element) in moved.enumerated() { element.order = index }
    }
}

public extension ModelContext {
    /// A new plan at the end of the list.
    @discardableResult
    func addPlan() -> Plan {
        let last = ((try? fetch(FetchDescriptor<Plan>())) ?? []).map(\.order).max() ?? -1
        let plan = Plan(name: String(localized: "New plan", bundle: .module), order: last + 1)
        insert(plan)
        return plan
    }

    /// Appends `exercise` to the end of `plan`.
    @discardableResult
    func add(_ exercise: String, to plan: Plan) -> PlanItem {
        let item = PlanItem(exercise: exercise, order: (plan.sortedItems.last?.order ?? -1) + 1)
        insert(item)
        item.plan = plan
        return item
    }
}
