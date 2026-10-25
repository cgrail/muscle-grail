#if os(iOS) || os(watchOS)
import HealthKit

@MainActor public enum Health {
    public static let store = HKHealthStore()
    private static var observing = false

    public static func requestAuthorization() async {
        let share: Set<HKSampleType> = [.workoutType(), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        let read: Set<HKObjectType> = [
            .workoutType(), HKQuantityType(.stepCount), HKQuantityType(.distanceWalkingRunning),
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

    /// Each day's total for the last `days` days, by the start of the day, as the Health app counts it.
    public static func daily(_ id: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async -> [Date: Double] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Calendar.current.startOfDay(for: .now))!
        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: start, end: nil)),
            options: .cumulativeSum, anchorDate: start, intervalComponents: DateComponents(day: 1)
        )
        guard let days = try? await query.result(for: store) else { return [:] }
        var totals: [Date: Double] = [:]
        days.enumerateStatistics(from: start, to: .now) { day, _ in totals[day.startDate] = day.sumQuantity()?.doubleValue(for: unit) }
        return totals
    }

    /// Every workout in Health since `date`, from any app or device, walks included: they count as activity.
    /// It arrives from the watch over Bluetooth, long before a gym workout's record syncs through iCloud.
    public static func workouts(since date: Date) async -> [(start: Date, id: UUID)] {
        let query = HKSampleQueryDescriptor(predicates: [.workout(HKQuery.predicateForSamples(withStart: date, end: nil))], sortDescriptors: [])
        return ((try? await query.result(for: store)) ?? []).map { ($0.startDate, $0.uuid) }
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
