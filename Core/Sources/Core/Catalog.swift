import Foundation

/// An exercise from free-exercise-db (public domain): https://github.com/yuhonas/free-exercise-db
/// `exercises.json` is its `dist/exercises.json`, bundled unchanged.
public struct CatalogExercise: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let equipment: String?
    public let primaryMuscles: [String]
    public let images: [String]
    public var instructions: [String] = []

    public static let all = load(Bundle.module.url(forResource: "exercises", withExtension: "json"))

    static func load(_ url: URL?) -> [CatalogExercise] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([CatalogExercise].self, from: data)) ?? []
    }

    // shortcut: images (~100 MB in total) load from GitHub, so they show placeholders offline; bundle thumbnails if plans get built offline
    public var imageURL: URL? {
        images.first.flatMap { URL(string: "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/\($0)") }
    }

    public var detail: String { (primaryMuscles + [equipment].compactMap { $0 }).joined(separator: " · ") }

    public var regions: Set<BodyRegion> { Set(primaryMuscles.compactMap(BodyRegion.init(muscle:))) }

    /// Whether it trains `region`; with no region, every exercise does.
    public func trains(_ region: BodyRegion?) -> Bool { region.map(regions.contains) ?? true }

    public func matches(_ query: String) -> Bool {
        matchesEveryWord(of: query, in: [name, equipment ?? ""] + primaryMuscles)
    }
}

/// Whether each word of `query` turns up somewhere in `fields`, ignoring case, hyphens and a plural "s":
/// "dumbbell curl" finds Dumbbell Bicep Curl, "squats" Barbell Squat and "pull-ups" Pullups.
public func matchesEveryWord(of query: String, in fields: [String]) -> Bool {
    query.split(whereSeparator: { $0 == " " || $0 == "-" }).allSatisfy { word in
        let singular = word.count > 3 && word.hasSuffix("s") ? word.dropLast() : word
        return fields.contains { $0.localizedCaseInsensitiveContains(singular) }
    }
}

/// The part of the body a catalog muscle belongs to, as lifters speak of a leg day or an arm day.
public enum BodyRegion: CaseIterable, Sendable {
    case legs, arms, chest, back, shoulders, core

    init?(muscle: String) {
        switch muscle {
        case "quadriceps", "hamstrings", "glutes", "calves", "adductors", "abductors": self = .legs
        case "biceps", "triceps", "forearms": self = .arms
        case "chest": self = .chest
        case "lats", "middle back", "lower back", "traps": self = .back
        case "shoulders", "neck": self = .shoulders
        case "abdominals": self = .core
        default: return nil
        }
    }

    public var name: String {
        switch self {
        case .legs: String(localized: "Legs", bundle: .module)
        case .arms: String(localized: "Arms", bundle: .module)
        case .chest: String(localized: "Chest", bundle: .module)
        case .back: String(localized: "Back", bundle: .module)
        case .shoulders: String(localized: "Shoulders", bundle: .module)
        case .core: String(localized: "Core", bundle: .module)
        }
    }

    var heavy: String {
        switch self {
        case .legs: String(localized: "Leg-heavy", bundle: .module)
        case .arms: String(localized: "Arm-heavy", bundle: .module)
        case .chest: String(localized: "Chest-heavy", bundle: .module)
        case .back: String(localized: "Back-heavy", bundle: .module)
        case .shoulders: String(localized: "Shoulder-heavy", bundle: .module)
        case .core: String(localized: "Core-heavy", bundle: .module)
        }
    }
}
