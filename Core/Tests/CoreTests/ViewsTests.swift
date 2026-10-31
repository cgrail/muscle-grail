#if os(macOS)
import AppKit
import SwiftData
import SwiftUI
import Testing
@testable import Core

/// Smoke tests: every view state renders. How it looks and feels is tested by hand.
@MainActor struct ViewsTests {
    let container = try! Store.makeContainer(inMemory: true)
    var context: ModelContext { container.mainContext }

    /// Every store a view was rendered with, kept for the whole run: SwiftUI can hold a taken-down view's SwiftData
    /// observers past its test, and once their store is gone they trap on a later test's save.
    private static var rendered: [ModelContainer] = []

    /// Renders in a real window, so lists build their rows and `onAppear` runs.
    func render(_ view: some View) {
        Self.rendered.append(container)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: view.modelContainer(container))
        window.displayIfNeeded()
        RunLoop.main.run(until: .now.addingTimeInterval(0.1))
        // The view goes while its test's store is still there: left behind, its SwiftData observers trapped on a later test's save.
        window.contentView = nil
    }

    @Test func planChangesRenderEmptyAndFull() throws {
        render(PlanChanges())
        let plan = makePlan(context, "Bench")
        try context.save()
        render(PlanChanges())
        render(PlanChanges(plan: plan.id))
    }

    @Test func activityGridRendersEveryLevel() {
        let today = Calendar.current.startOfDay(for: .now)
        let daysAgo = { (days: Int) in Calendar.current.date(byAdding: .day, value: -days, to: today)! }
        let weeks = activityWeeks(gym: [today], steps: [daysAgo(1): 12_000, daysAgo(2): 3_000], stepGoal: 10_000, weeks: 53)
        render(ActivityGrid(weeks: weeks, selected: .constant(today)))
    }

    @Test func unreadableStoreRenders() {
        render(UnreadableStore(OpenStore { throw CocoaError(.fileReadCorruptFile) }))
    }

    @Test func syncStatusRendersEveryState() {
        let prefs = TestDefaults()
        let sync = SyncMonitor(defaults: prefs.defaults)
        render(SyncStatusView(sync: sync))
        let running = UUID()
        sync.update(id: running, finished: false, isSync: true, error: nil)
        render(SyncStatusView(sync: sync))
        sync.saved(at: .now)
        sync.update(id: running, finished: true, isSync: true, error: nil)
        render(SyncStatusView(sync: sync))
        sync.update(id: UUID(), finished: true, isSync: true, error: nil, exportStart: .now)
        render(SyncStatusView(sync: sync))
        sync.update(id: UUID(), finished: true, isSync: true, error: "Offline")
        render(SyncStatusView(sync: sync))
    }

    @Test func emptyWorkoutPickerRenders() {
        render(NavigationStack { WorkoutPicker { _ in } })
    }

    @Test func showingWorkoutPickerStartsNoWorkout() throws {
        context.log("Bench", reps: 8, weightKg: 60, in: context.startWorkout(makePlan(context, "Bench")))
        render(NavigationStack { WorkoutPicker { _ in } })
        #expect(try context.fetchCount(FetchDescriptor<Workout>()) == 1)
    }

    @Test func weightStepperRendersInTheExercisesUnit() {
        let id = context.createExercise(named: "Cable Fly")
        context.setUnit(id, to: .lb)
        render(Form { ExerciseName(id); WeightStepper(kg: .constant(20), exerciseID: id) })
    }
}
#endif
