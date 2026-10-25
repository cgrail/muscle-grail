#if os(iOS) || os(watchOS)
import HealthKit

@MainActor public enum Health {
    public static let store = HKHealthStore()
    private static var observing = false

    public static func requestAuthorization() async {
        let share: Set<HKSampleType> = [.workoutType(), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        let read: Set<HKObjectType> = [
            HKQuantityType(.stepCount), HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned),
        ]
        try? await store.requestAuthorization(toShare: share, read: read)
    }

    /// Today's total as the Health app shows it (HealthKit de-duplicates iPhone and Watch samples).
    public static func today(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double {
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: .now), end: nil)
        let query = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: predicate), options: .cumulativeSum
        )
        return try await query.result(for: store)?.sumQuantity()?.doubleValue(for: unit) ?? 0
    }

    /// New steps wake the app in the background about hourly. Every wake gives CloudKit a chance to sync,
    /// which keeps this device current without opening the app. Call at every launch, background ones included.
    public static func observeSteps(onWake: @escaping @MainActor @Sendable () async -> Void) {
        guard !observing, store.authorizationStatus(for: .workoutType()) != .notDetermined else { return }
        observing = true
        let steps = HKQuantityType(.stepCount)
        store.execute(HKObserverQuery(sampleType: steps, predicate: nil) { _, completion, _ in
            nonisolated(unsafe) let completion = completion // HealthKit allows calling it from any thread
            Task { @MainActor in
                await onWake()
                completion()
            }
        })
        store.enableBackgroundDelivery(for: steps, frequency: .hourly) { _, _ in }
    }

    /// Saves a finished phone workout and returns its HealthKit id. The watch saves its own through its workout session.
    public static func save(_ workout: Workout) async -> UUID? {
        guard workout.healthKitID == nil, let end = workout.end else { return nil }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: workout.start)
            try await builder.endCollection(at: end)
            return try await builder.finishWorkout()?.uuid
        } catch {
            return nil // Health access denied or unavailable: the workout stays in the app, just not in Health.
        }
    }
}
#endif
