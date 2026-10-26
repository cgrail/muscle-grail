import CoreGraphics
import Foundation
import ImageIO
import SwiftData
@testable import Core

/// A plan with these exercises (catalog ids), in order.
@MainActor @discardableResult
func makePlan(_ context: ModelContext, _ exercises: String...) -> Plan {
    let plan = context.addPlan()
    for exercise in exercises { context.add(exercise, to: plan) }
    return plan
}

/// The plans' history as the apps read it: what's saved, in a context of its own.
@MainActor func history(_ container: ModelContainer, of plan: Plan? = nil) throws -> [PlanChange] {
    try container.mainContext.save()
    return try PlanChange.history(container, plan: plan?.id)
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
        "item \($0.id) \(String(describing: $0.plan?.id)) \($0.exerciseID) \($0.order) \($0.targetSets) \($0.targetReps) \($0.targetWeightKg)"
    }
    let workouts = try context.fetch(FetchDescriptor<Workout>()).map {
        "workout \($0.id) \(String(describing: $0.plan?.id)) \($0.start) \(String(describing: $0.end)) \(String(describing: $0.healthKitID))"
    }
    let sets = try context.fetch(FetchDescriptor<LoggedSet>()).map {
        "set \($0.id) \(String(describing: $0.workout?.id)) \($0.exerciseID) \($0.reps) \($0.weightKg) \($0.date.timeIntervalSinceReferenceDate)"
    }
    let catalog = try context.fetch(FetchDescriptor<CatalogEntry>()).map {
        "entry \($0.id) \($0.name) \($0.details) \($0.videoURL) \(String(describing: $0.photo))"
    }
    return (plans + items + workouts + sets + catalog).sorted()
}

/// A PNG of the given size, as the photo library would hand one over.
func testPhoto(width: Int = 40, height: Int = 20) -> Data {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(red: 1, green: 0.5, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}
