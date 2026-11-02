#if os(macOS)
import SwiftData
import SwiftUI

/// The Mac's Train page, like Apple Music's Home: a running workout to continue, the plan next up large with what's in it,
/// then the other plans as covers, in `trainingOrder`. Clicking a plan opens it to train, once no workout runs; its workout
/// starts with the first set logged.
public struct TrainOverview: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Plan.order) private var plans: [Plan]
    @Query(Workout.unfinished) private var unfinished: [Workout]
    private let onContinue: (Workout) -> Void
    private let onStart: (Plan) -> Void

    public init(onContinue: @escaping (Workout) -> Void, onStart: @escaping (Plan) -> Void) {
        (self.onContinue, self.onStart) = (onContinue, onStart)
    }

    public var body: some View {
        let training = !unfinished.isEmpty
        let order = trainingOrder(plans)
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                ForEach(unfinished) { running($0) }
                if let next = order.first {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Next up", bundle: .module).font(.title2.bold())
                        nextUp(next)
                    }
                    .disabled(training).opacity(training ? 0.5 : 1)
                }
                if order.count > 1 {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("After that", bundle: .module).font(.title2.bold())
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 160), spacing: 24, alignment: .top)], alignment: .leading, spacing: 28) {
                            ForEach(order.dropFirst()) { cover($0) }
                        }
                    }
                    .disabled(training).opacity(training ? 0.5 : 1)
                }
                if plans.isEmpty {
                    Text("No plans yet. Create one under Plans.", bundle: .module).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
        .navigationTitle(Text("Train", bundle: .module))
        .task(id: plans.count) { await PhotoCache.shared.download(plans.flatMap { $0.trainedItems.map(\.exerciseID) }) }
    }

    private func running(_ workout: Workout) -> some View {
        HStack(spacing: 16) {
            if let plan = workout.plan { PlanPicture(plan, size: 64) }
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.title).font(.title2.bold())
                Text("Finish the running workout to start another.", bundle: .module).foregroundStyle(.secondary)
            }
            Spacer()
            Button { onContinue(workout) } label: { Label { Text("Continue", bundle: .module) } icon: { Image(systemName: "play.fill") } }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(16)
        .background((workout.plan?.color ?? .green).opacity(0.15), in: .rect(cornerRadius: 20))
    }

    private func nextUp(_ plan: Plan) -> some View {
        HStack(spacing: 24) {
            PlanPicture(plan, size: 180).shadow(radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 6) {
                Text(plan.title).font(.largeTitle.bold())
                if let motto = plan.motto { Text(verbatim: motto).italic().foregroundStyle(.secondary) }
                if let focus = plan.focus { Text(verbatim: focus).font(.title3).foregroundStyle(plan.color) }
                Text(verbatim: plan.lastDoneText).foregroundStyle(.secondary)
                Text(verbatim: plan.trainedItems.map { context.exerciseName($0.exerciseID) }.joined(separator: " · "))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Button { onStart(plan) } label: { Label { Text("Start", bundle: .module) } icon: { Image(systemName: "play.fill") } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(plan.color)
                    .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(plan.color.opacity(0.12), in: .rect(cornerRadius: 24))
    }

    private func cover(_ plan: Plan) -> some View {
        Button { onStart(plan) } label: {
            VStack(alignment: .leading, spacing: 3) {
                PlanPicture(plan, size: 160).shadow(radius: 4, y: 2).padding(.bottom, 6)
                Text(plan.title).font(.headline).lineLimit(1)
                if let focus = plan.focus { Text(verbatim: focus).foregroundStyle(plan.color) }
                let special = specialExercises(of: plan, among: plans).map { context.exerciseName($0) }
                if !special.isEmpty { Text(verbatim: special.joined(separator: ", ")).lineLimit(2) }
                Text(verbatim: plan.lastDoneText).foregroundStyle(.secondary)
            }
            .frame(width: 160, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
#endif
