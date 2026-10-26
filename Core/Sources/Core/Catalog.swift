import Foundation

/// An exercise from RepDB's free dataset (https://github.com/RepDB/exercise-dataset), which `fetch-catalog.sh` downloads
/// into `RepDB/` at `repdbCommit`. Its license wants "Exercise data by RepDB (repdb.co)" visible in the app and the README.
public struct CatalogExercise: Identifiable, Sendable {
    /// The RepDB commit the catalog and its images come from. Plans and sets refer to its ids: a new commit must keep them.
    static let repdbCommit = "b407c5951a027a27817fb2a5cee9ec9feffc4dc7"

    public let id: String
    public let name: String
    public let equipment: String?
    public let primaryMuscles: [String]
    /// Paths in RepDB's repository, the starting pose first.
    public let images: [String]
    public var instructions: [String] = []
    public var level: String?
    public var category: String?
    var germanName = ""
    var germanInstructions: [String] = []

    public static let all = load(Bundle.module.url(forResource: "exercises", withExtension: "json", subdirectory: "RepDB"))

    static func load(_ url: URL?) -> [CatalogExercise] {
        struct Dataset: Decodable { let exercises: [CatalogExercise] }
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode(Dataset.self, from: data).exercises) ?? []
    }

    // shortcut: images (~20 MB in total) load from RepDB's GitHub, so they show placeholders offline; bundle thumbnails if plans get built offline
    public var imageURL: URL? {
        images.first.flatMap { URL(string: "https://raw.githubusercontent.com/RepDB/exercise-dataset/\(Self.repdbCommit)/\($0)") }
    }

    /// Whether the app runs in German, which RepDB has names and steps for. It only changes with a relaunch.
    static let german = Bundle.module.preferredLocalizations.first == "de"

    /// The name in the user's language. `name` stays English: Claude and the assistant look exercises up by it.
    public var label: String { Self.german && !germanName.isEmpty ? germanName : name }

    /// How to do it, a paragraph per step, in the user's language.
    public var steps: [String] { Self.german && !germanInstructions.isEmpty ? germanInstructions : instructions }

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

    /// The catalog in the order of its names in the user's language.
    public static let alphabetical = all.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
}

extension CatalogExercise: Decodable {
    enum CodingKeys: String, CodingKey {
        case id, equipment, images, category
        case name = "name_en", germanName = "name_de", instructions = "instructions_en", germanInstructions = "instructions_de"
        case primaryMuscles = "primary_muscles", level = "difficulty"
    }

    public init(from decoder: any Decoder) throws {
        struct Images: Decodable { let flat: [String: String] }
        let row = try decoder.container(keyedBy: CodingKeys.self)
        let flat = try row.decodeIfPresent(Images.self, forKey: .images)?.flat ?? [:]
        self.init(
            id: try row.decode(String.self, forKey: .id),
            name: try row.decode(String.self, forKey: .name),
            equipment: try row.decodeIfPresent(String.self, forKey: .equipment), // absent for bodyweight moves
            primaryMuscles: try row.decodeIfPresent([String].self, forKey: .primaryMuscles) ?? [],
            images: ["start", "main", "peak"].compactMap { flat[$0] },
            instructions: try row.decodeIfPresent([String].self, forKey: .instructions) ?? [],
            level: try row.decodeIfPresent(String.self, forKey: .level),
            category: try row.decodeIfPresent(String.self, forKey: .category),
            germanName: try row.decodeIfPresent(String.self, forKey: .germanName) ?? "",
            germanInstructions: try row.decodeIfPresent([String].self, forKey: .germanInstructions) ?? []
        )
    }
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

    /// What `key` holds across the catalog, most common first: intermediate before advanced, strength before cardio.
    static func values(_ key: KeyPath<CatalogExercise, String?>) -> [String] {
        let counts = Dictionary(CatalogExercise.all.compactMap { $0[keyPath: key] }.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.keys.sorted { (counts[$0]!, $1) > (counts[$1]!, $0) }
    }
}

/// A muscle, level, piece of equipment or category in the user's language: RepDB has them as English keys only.
public func catalogTerm(_ term: String) -> String { String(localized: String.LocalizationValue(term), bundle: .module) }

/// Whether each word of `query` turns up somewhere in `fields`, ignoring case, hyphens and a plural "s":
/// "dumbbell curl" finds Dumbbell Bicep Curl, "squats" Barbell Back Squat and "lat-pulldowns" Lat Pulldown.
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
        case "quadriceps", "hamstrings", "gluteus_maximus", "gluteus_medius", "adductors", "abductors", "gastrocnemius", "soleus",
             "hip_flexors", "tibialis_anterior": self = .legs
        case "biceps_brachii", "triceps_brachii", "brachialis", "brachioradialis", "forearm_extensors", "forearm_flexors": self = .arms
        case "pectoralis_major": self = .chest
        case "latissimus_dorsi", "rhomboids", "trapezius", "erector_spinae", "quadratus_lumborum": self = .back
        case "anterior_deltoid", "lateral_deltoid", "posterior_deltoid": self = .shoulders
        case "rectus_abdominis", "obliques", "transverse_abdominis": self = .core
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
