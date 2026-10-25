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

    /// Renders in a real window, so lists build their rows and `onAppear` runs.
    func render(_ view: some View) {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: view.modelContainer(container))
        window.displayIfNeeded()
        RunLoop.main.run(until: .now.addingTimeInterval(0.1))
    }

    @Test func syncStatusRendersEveryState() {
        let prefs = TestDefaults()
        let sync = SyncMonitor(defaults: prefs.defaults)
        render(SyncStatusView(sync: sync))
        sync.update(id: UUID(), finished: true, isSync: true, error: nil)
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

    @Test func exerciseSectionRendersLoggedSets() {
        let plan = makePlan(context, "Bench")
        let workout = context.startWorkout(plan)
        context.log("Bench", reps: 8, weightKg: 60, in: workout)
        render(List { ExerciseSection(item: plan.sortedItems[0], workout: workout) })
    }

    @Test func exerciseRowRendersOpenAndFinished() {
        let plan = makePlan(context, "Bench", "Squat")
        let workout = context.startWorkout(plan)
        context.setTargets(plan.sortedItems[1], sets: 1, weightKg: 0)
        context.log("Squat", reps: 10, weightKg: 0, in: workout)
        render(NavigationStack { List(plan.sortedItems) { ExerciseRow(item: $0, workout: workout) } })
    }

    @Test func exerciseSectionRendersYourOwnPhoto() {
        let id = context.createExercise(named: "Cable Fly")
        context.setPhoto(id, to: testPhoto())
        let plan = makePlan(context, id)
        render(List { ExerciseSection(item: plan.sortedItems[0], workout: context.startWorkout(plan)) })
    }
}
#endif
