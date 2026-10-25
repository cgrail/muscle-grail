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
    public var level: String?
    public var category: String?

    public static let all = load(Bundle.module.url(forResource: "exercises", withExtension: "json"))

    static func load(_ url: URL?) -> [CatalogExercise] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([CatalogExercise].self, from: data)) ?? []
    }

    // shortcut: images (~100 MB in total) load from GitHub, so they show placeholders offline; bundle thumbnails if plans get built offline
    public var imageURL: URL? {
        images.first.flatMap { URL(string: "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/\($0)") }
    }

    /// The name in the user's language. `name` stays English: it is the catalog's data, and Claude and the assistant look exercises up by it.
    public var label: String { translated(name) }

    /// Its muscles, then its equipment, in the user's language.
    public var detail: String { (primaryMuscles + [equipment].compactMap { $0 }).map(catalogTerm).joined(separator: " · ") }

    public var regions: Set<BodyRegion> { Set(primaryMuscles.compactMap(BodyRegion.init(muscle:))) }

    /// Whether it trains `region`; with no region, every exercise does.
    public func trains(_ region: BodyRegion?) -> Bool { region.map(regions.contains) ?? true }

    /// Whether every word of `query` is in its name, muscles or equipment, in English or the user's language.
    public func matches(_ query: String) -> Bool {
        let terms = primaryMuscles + [equipment].compactMap { $0 }
        return matchesEveryWord(of: query, in: [name, label] + terms + terms.map(catalogTerm))
    }

    /// The catalog in the order of its names in the user's language, which only changes with a relaunch.
    public static let alphabetical = all.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
}

/// A name or step of the catalog in the user's language: `Exercises.xcstrings` has them keyed by the English text.
func translated(_ text: String, bundle: Bundle = .module) -> String {
    bundle.localizedString(forKey: text, value: nil, table: "Exercises")
}

/// Narrows the catalog to one body region, level, piece of equipment and category; nil lets every exercise through.
public struct CatalogFilter: Equatable, Sendable {
    public var region: BodyRegion?
    public var level: String?
    public var equipment: String?
    public var category: String?

    public init() {}

    /// The user's own exercises have none of these, so a filter that isn't empty hides them.
    public var isEmpty: Bool { self == CatalogFilter() }

    public func admits(_ exercise: CatalogExercise) -> Bool {
        exercise.trains(region) && [(level, exercise.level), (equipment, exercise.equipment), (category, exercise.category)]
            .allSatisfy { chosen, value in chosen == nil || chosen == value }
    }

    public static let levels = values(\.level)
    public static let equipment = values(\.equipment)
    public static let categories = values(\.category)

    /// What `key` holds across the catalog, most common first: beginner before expert, strength before cardio.
    static func values(_ key: KeyPath<CatalogExercise, String?>) -> [String] {
        let counts = Dictionary(CatalogExercise.all.compactMap { $0[keyPath: key] }.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.keys.sorted { (counts[$0]!, $1) > (counts[$1]!, $0) }
    }
}

/// A muscle, level, piece of equipment or category in the user's language: the catalog has them in English only.
public func catalogTerm(_ term: String) -> String { String(localized: String.LocalizationValue(term), bundle: .module) }

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
