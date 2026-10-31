#if targetEnvironment(simulator)
import Core
import SwiftData

/// Launched with `-sampleData` (an argument to tick in the MuscleGrailWatch scheme), the simulator gets a plan to train with
/// while its store has none: without an iCloud account no plan syncs to it. Simulator only, so no device uploads it to iCloud.
enum SampleData {
    static func addIfAsked(to context: ModelContext) {
        guard CommandLine.arguments.contains("-sampleData"), (try? context.fetchCount(FetchDescriptor<Plan>())) == 0 else { return }
        let plan = context.addPlan()
        context.rename(plan, to: "Sample workout")
        // A weight like the gym's 47.5 kg, a wide one, a long German name and a bodyweight exercise, to check what fits.
        context.add([
            PlannedExercise(name: "Barbell Bench Press", sets: 3, reps: 10, weightKg: 47.5),
            PlannedExercise(name: "Leg Press", sets: 3, reps: 12, weightKg: 102.5),
            PlannedExercise(name: "Wide Grip Seated Cable Row", sets: 3, reps: 10, weightKg: 40),
            PlannedExercise(name: "Pull-Up", sets: 3, reps: 8, weightKg: 0),
        ], to: plan)
        try? context.save()
    }
}
#endif
