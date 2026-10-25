import Core
import HealthKit
import SwiftUI
import WidgetKit

struct StepsEntry: TimelineEntry {
    var date = Date.now
    var steps = 0.0
    var km = 0.0
}

struct StepsProvider: TimelineProvider {
    func placeholder(in context: Context) -> StepsEntry { StepsEntry(steps: 10_847, km: 6.7) }

    func getSnapshot(in context: Context, completion: @escaping (StepsEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StepsEntry>) -> Void) {
        Task {
            let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
            let entries = [await Self.today(), StepsEntry(date: midnight)]
            // The watch app also reloads this whenever HealthKit reports new steps.
            completion(Timeline(entries: entries, policy: .after(.now.addingTimeInterval(15 * 60))))
        }
    }

    /// HealthKit can't be read while the watch is locked, so fall back to the last value read today.
    private static func today() async -> StepsEntry {
        let defaults = UserDefaults.standard
        do {
            async let steps = Health.today(.stepCount, unit: .count())
            async let km = Health.today(.distanceWalkingRunning, unit: .meterUnit(with: .kilo))
            let entry = try await StepsEntry(steps: steps, km: km)
            defaults.set(Date.now, forKey: "day")
            defaults.set(entry.steps, forKey: "steps")
            defaults.set(entry.km, forKey: "km")
            return entry
        } catch {
            guard let day = defaults.object(forKey: "day") as? Date, Calendar.current.isDateInToday(day) else { return StepsEntry() }
            return StepsEntry(steps: defaults.double(forKey: "steps"), km: defaults.double(forKey: "km"))
        }
    }
}

struct StepsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StepsEntry

    var body: some View {
        let steps = entry.steps.formatted(.number.precision(.fractionLength(0)))
        let km = entry.km.formatted(.number.precision(.fractionLength(1)))
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Label(steps, systemImage: "shoeprints.fill").font(.headline)
                Label("\(km) km", systemImage: "figure.walk")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            Text("\(steps) steps · \(km) km")
        case .accessoryCorner:
            Image(systemName: "shoeprints.fill").widgetLabel("\(steps) steps")
        default:
            VStack {
                Image(systemName: "shoeprints.fill")
                Text(entry.steps.formatted(.number.notation(.compactName)))
            }
        }
    }
}

@main
struct StepsComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Steps", provider: StepsProvider()) { entry in
            StepsView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Steps")
        .description("Today's steps and walking distance. Tapping it opens Muscle Grail.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline, .accessoryCorner])
    }
}
